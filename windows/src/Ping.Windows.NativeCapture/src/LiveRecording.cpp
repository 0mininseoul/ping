#include "LiveRecording.h"
#include <algorithm>
#include <chrono>
#include <stdexcept>

namespace Ping::Windows::NativeCapture
{
    namespace { constexpr int SkipFrame = -1; }
    LONGLONG CaptureClockNow()
    {
        LARGE_INTEGER counter{}, frequency{};
        if (!QueryPerformanceCounter(&counter) || !QueryPerformanceFrequency(&frequency) || frequency.QuadPart <= 0)
            throw std::runtime_error("Performance clock unavailable");
        return static_cast<LONGLONG>(static_cast<long double>(counter.QuadPart) * 10'000'000 / frequency.QuadPart);
    }

    RecordingSourceState::RecordingSourceState(OutputLayout layout, int durationMs, std::function<LONGLONG()> clock)
        : Layout(layout), clock_(std::move(clock)), buffer_(layout), targetSamples_(static_cast<std::uint64_t>(durationMs) * 48)
    {
        if (durationMs <= 0 || durationMs > 30'000) Fail(PingCaptureCaptureFailure);
    }

    int RecordingSourceState::SubmitVideoTime(RecordingSourceKind kind, LONGLONG qpcTime, LONGLONG& relative)
    {
        std::lock_guard guard(mutex_);
        if (error_ != PingCaptureSuccess) return error_;
        if (qpcTime < 0) return PingCaptureCaptureFailure;
        relative = start_ < 0 ? 0 : qpcTime - start_;
        if (relative < 0 || relative > 300'000'000LL) return SkipFrame;
        auto& last = kind == RecordingSourceKind::Screen ? lastScreen_ : lastCamera_;
        if (start_ >= 0 && last >= 0 && relative - last < 10'000'000 / 30 - 5'000) return SkipFrame;
        last = relative;
        ready_ |= static_cast<int>(kind); changed_.notify_all();
        return PingCaptureSuccess;
    }

    int RecordingSourceState::SubmitScreen(std::unique_ptr<MonitorCaptureResult> frame, LONGLONG qpcTime)
    {
        LONGLONG relative = 0;
        auto result = SubmitVideoTime(RecordingSourceKind::Screen, qpcTime, relative);
        if (result != PingCaptureSuccess) return result == SkipFrame ? PingCaptureSuccess : result;
        result = buffer_.PublishScreen(std::move(frame), relative);
        if (result != PingCaptureSuccess) Fail(result);
        return result;
    }

    int RecordingSourceState::SubmitCamera(std::unique_ptr<CameraFrameResult> frame, LONGLONG qpcTime)
    {
        LONGLONG relative = 0;
        auto result = SubmitVideoTime(RecordingSourceKind::Camera, qpcTime, relative);
        if (result != PingCaptureSuccess) return result == SkipFrame ? PingCaptureSuccess : result;
        result = buffer_.PublishCamera(std::move(frame), relative);
        if (result != PingCaptureSuccess) Fail(result);
        return result;
    }

    int RecordingSourceState::SubmitAudio(std::uint64_t devicePosition, LONGLONG qpcTime, std::vector<std::uint8_t> const& pcm)
    {
        std::uint64_t first = 0, samples = 0;
        {
            std::lock_guard guard(mutex_);
            if (error_ != PingCaptureSuccess) return error_;
            if (qpcTime < 0 || pcm.empty() || pcm.size() % 2 != 0 || pcm.size() > 48'000) return PingCaptureNoMicrophone;
            ready_ |= static_cast<int>(RecordingSourceKind::Audio); changed_.notify_all();
            if (!armed_ || (ready_ & 3) != 3) return PingCaptureSuccess;
            if (start_ < 0)
            {
                start_ = qpcTime; audioBase_ = devicePosition; audioNext_ = devicePosition;
                changed_.notify_all();
            }
            if (audioNext_ - audioBase_ >= targetSamples_) return PingCaptureSuccess;
            if (devicePosition != audioNext_) return PingCaptureNoMicrophone;
            first = devicePosition - audioBase_;
            samples = std::min<std::uint64_t>(pcm.size() / 2, targetSamples_ - first);
            audioNext_ += samples;
        }
        std::vector<std::uint8_t> selected(pcm.begin(), pcm.begin() + static_cast<std::ptrdiff_t>(samples * 2));
        auto result = buffer_.PublishAudio(first, selected);
        if (result != PingCaptureSuccess) Fail(result);
        return result;
    }

    int RecordingSourceState::ErrorLocked(HANDLE cancellation)
    {
        if (cancellation && WaitForSingleObject(cancellation, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;
        return error_;
    }

    int RecordingSourceState::WaitStart(HANDLE cancellation)
    {
        auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        std::unique_lock lock(mutex_); armed_ = true;
        while (true)
        {
            auto error = ErrorLocked(cancellation);
            if (error != PingCaptureSuccess) return error;
            if (start_ >= 0) return PingCaptureSuccess;
            if (std::chrono::steady_clock::now() >= deadline) return PingCaptureCaptureFailure;
            changed_.wait_for(lock, std::chrono::milliseconds(10));
        }
    }

    int RecordingSourceState::WaitFrameTime(LONGLONG time, HANDLE cancellation)
    {
        std::unique_lock lock(mutex_);
        if (start_ < 0 || time < 0 || time > 300'000'000) return PingCaptureCaptureFailure;
        while (true)
        {
            auto error = ErrorLocked(cancellation);
            if (error != PingCaptureSuccess) return error;
            auto remaining = start_ + time - clock_();
            if (remaining <= 0) return PingCaptureSuccess;
            changed_.wait_for(lock, std::chrono::milliseconds(std::clamp<LONGLONG>(remaining / 10'000, 1, 10)));
        }
    }

    int RecordingSourceState::ReadFrame(LONGLONG time, LONGLONG duration, RecordingFramePacket& packet, HANDLE cancellation)
    {
        auto result = WaitFrameTime(time, cancellation);
        return result == PingCaptureSuccess ? buffer_.ReadFrame(time, duration, packet, cancellation) : result;
    }

    void RecordingSourceState::Fail(int error) noexcept
    {
        { std::lock_guard guard(mutex_); if (error_ == PingCaptureSuccess) error_ = error; }
        buffer_.Fail(error); changed_.notify_all();
    }
    void RecordingSourceState::Close() noexcept { Fail(PingCaptureCancelled); }

    RecordingSourceWorker::RecordingSourceWorker(std::shared_ptr<RecordingSourceState> state) : State(std::move(state))
    {
        stopEvent_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (!stopEvent_) throw std::runtime_error("Capture stop event unavailable");
    }
    RecordingSourceWorker::~RecordingSourceWorker() { RequestStop(); WaitStopped(); CloseHandle(stopEvent_); }
    void RecordingSourceWorker::Start()
    {
        if (worker_.joinable()) throw std::logic_error("Capture source already started");
        worker_ = std::thread([this] {
            try { auto result = Run(stopEvent_); if (result != PingCaptureSuccess) State->Fail(result); }
            catch (...) { State->Fail(PingCaptureCaptureFailure); }
        });
    }
    void RecordingSourceWorker::RequestStop() noexcept { SetEvent(stopEvent_); }
    void RecordingSourceWorker::WaitStopped() noexcept { if (worker_.joinable()) worker_.join(); }

    LiveRecordingProvider::LiveRecordingProvider(std::shared_ptr<RecordingSourceState> state,
        std::vector<std::unique_ptr<IRecordingSource>> sources) : state_(std::move(state)), sources_(std::move(sources)) {}
    LiveRecordingProvider::~LiveRecordingProvider() { Stop(); }
    int LiveRecordingProvider::ReadFrame(LONGLONG time, LONGLONG duration, RecordingFramePacket& packet, HANDLE cancellation)
    {
        if (stopped_) return PingCaptureCancelled;
        if (!started_)
        {
            started_ = true;
            for (auto const& source : sources_) source->Start();
            auto result = state_->WaitStart(cancellation);
            if (result != PingCaptureSuccess) return result;
        }
        return state_->ReadFrame(time, duration, packet, cancellation);
    }
    void LiveRecordingProvider::Stop() noexcept
    {
        if (stopped_) return;
        stopped_ = true; state_->Close();
        for (auto const& source : sources_) source->RequestStop();
        for (auto const& source : sources_) source->WaitStopped();
    }
}
