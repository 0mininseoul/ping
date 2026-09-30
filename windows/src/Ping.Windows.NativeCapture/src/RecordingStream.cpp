#include "RecordingStream.h"
#include <algorithm>
#include <chrono>

namespace
{
    constexpr size_t AudioCapacity = 48'000; // 500ms of48kHz mono16-bit PCM.
    constexpr LONGLONG OneSecond = 10'000'000;
    bool Cancelled(HANDLE event) { return event && WaitForSingleObject(event, 0) == WAIT_OBJECT_0; }
    bool ValidPixels(Ping::Windows::NativeCapture::CaptureSize size, std::uint32_t pitch, size_t bytes,
        int expectedWidth, int expectedHeight)
    {
        return size.Width == expectedWidth && size.Height == expectedHeight && size.Width > 0 && size.Height > 0
            && pitch == static_cast<std::uint32_t>(size.Width) * 4 && bytes == static_cast<size_t>(pitch) * size.Height;
    }
}

namespace Ping::Windows::NativeCapture
{
    BoundedRecordingBuffer::BoundedRecordingBuffer(OutputLayout layout) : layout_(layout), audio_(AudioCapacity)
    {
        if (layout.Width < 2 || layout.Height < 2 || layout.Width > 540 || layout.Height > 540
            || layout.FaceDiameter < 1 || layout.FaceDiameter > std::min(layout.Width, layout.Height))
            FailLocked(PingCaptureCaptureFailure);
    }

    int BoundedRecordingBuffer::FailLocked(int error) noexcept
    {
        if (error_ == PingCaptureSuccess) error_ = error == PingCaptureSuccess ? PingCaptureCaptureFailure : error;
        screen_.reset(); camera_.reset();
        std::vector<std::uint8_t>().swap(audio_); audioSize_ = 0;
        changed_.notify_all();
        return error_;
    }

    int BoundedRecordingBuffer::PublishScreen(std::unique_ptr<MonitorCaptureResult> frame, LONGLONG timestamp)
    {
        std::lock_guard guard(mutex_);
        if (error_ != PingCaptureSuccess) return error_;
        if (!frame || timestamp < 0 || timestamp < screenTime_
            || !ValidPixels(frame->SourceSize, frame->RowPitch, frame->BgraPixels.size(), layout_.Width, layout_.Height)
            || frame->BgraPixels.capacity() > frame->BgraPixels.size())
            return FailLocked(PingCaptureCaptureFailure);
        screen_ = std::move(frame); screenTime_ = timestamp;
        changed_.notify_all(); return PingCaptureSuccess;
    }

    int BoundedRecordingBuffer::PublishCamera(std::unique_ptr<CameraFrameResult> frame, LONGLONG timestamp)
    {
        std::lock_guard guard(mutex_);
        if (error_ != PingCaptureSuccess) return error_;
        if (!frame || timestamp < 0 || timestamp < cameraTime_
            || !ValidPixels(frame->SourceSize, frame->RowPitch, frame->BgraPixels.size(), layout_.FaceDiameter, layout_.FaceDiameter)
            || frame->BgraPixels.capacity() > frame->BgraPixels.size())
            return FailLocked(PingCaptureNoCamera);
        camera_ = std::move(frame); cameraTime_ = timestamp;
        changed_.notify_all(); return PingCaptureSuccess;
    }

    int BoundedRecordingBuffer::PublishAudio(std::uint64_t firstSample, std::vector<std::uint8_t> const& pcm)
    {
        std::lock_guard guard(mutex_);
        if (error_ != PingCaptureSuccess) return error_;
        if (pcm.empty() || pcm.size() % 2 != 0 || firstSample != publishedSamples_ || pcm.size() > AudioCapacity - audioSize_)
            return FailLocked(PingCaptureNoMicrophone);
        auto tail = (audioHead_ + audioSize_) % AudioCapacity;
        for (size_t i = 0; i < pcm.size(); ++i) audio_[(tail + i) % AudioCapacity] = pcm[i];
        audioSize_ += pcm.size(); publishedSamples_ += pcm.size() / 2;
        changed_.notify_all(); return PingCaptureSuccess;
    }

    int BoundedRecordingBuffer::ReadFrame(LONGLONG time, LONGLONG duration, RecordingFramePacket& packet,
        HANDLE cancellationEvent, int timeoutMs)
    {
        packet = {};
        if (time < 0 || duration <= 0 || duration > OneSecond || time > 30 * OneSecond - duration || timeoutMs < 0 || timeoutMs > 10'000)
            return PingCaptureCaptureFailure;
        const auto first = static_cast<std::uint64_t>(time) * 48'000 / OneSecond;
        const auto end = static_cast<std::uint64_t>(time + duration) * 48'000 / OneSecond;
        const auto bytes = static_cast<size_t>(end - first) * 2;
        auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeoutMs);
        std::unique_lock lock(mutex_);
        if (first != consumedSamples_ || bytes > AudioCapacity || bytes == 0) return FailLocked(PingCaptureCaptureFailure);
        while (true)
        {
            if (Cancelled(cancellationEvent)) return FailLocked(PingCaptureCancelled);
            if (error_ != PingCaptureSuccess) return error_;
            if (screen_ && camera_ && audioSize_ >= bytes) break;
            if (std::chrono::steady_clock::now() >= deadline) return FailLocked(PingCaptureCaptureFailure);
            changed_.wait_until(lock, std::min(deadline, std::chrono::steady_clock::now() + std::chrono::milliseconds(10)));
        }
        // Do not substitute frames from a different time when a producer/encoder falls behind.
        if (screenTime_ > time + duration || cameraTime_ > time + duration
            || screenTime_ < time - OneSecond / 5 || cameraTime_ < time - OneSecond / 5)
            return FailLocked(PingCaptureCaptureFailure);
        packet.Screen = screen_; packet.Camera = camera_;
        packet.Audio.resize(bytes);
        for (size_t i = 0; i < bytes; ++i) packet.Audio[i] = audio_[(audioHead_ + i) % AudioCapacity];
        audioHead_ = (audioHead_ + bytes) % AudioCapacity; audioSize_ -= bytes; consumedSamples_ = end;
        return PingCaptureSuccess;
    }

    void BoundedRecordingBuffer::Fail(int error) noexcept { std::lock_guard guard(mutex_); FailLocked(error); }
    void BoundedRecordingBuffer::Close() noexcept { Fail(PingCaptureCancelled); }
    size_t BoundedRecordingBuffer::RetainedBytes() const noexcept
    {
        std::lock_guard guard(mutex_);
        return (screen_ ? screen_->BgraPixels.capacity() : 0) + (camera_ ? camera_->BgraPixels.capacity() : 0) + audio_.capacity();
    }
}
