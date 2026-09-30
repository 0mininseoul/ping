#pragma once
#include "RecordingStream.h"
#include <atomic>
#include <functional>
#include <thread>

namespace Ping::Windows::NativeCapture
{
    LONGLONG CaptureClockNow();
    enum class RecordingSourceKind { Screen = 1, Camera = 2, Audio = 4 };

    class RecordingSourceState
    {
    public:
        RecordingSourceState(OutputLayout layout, int durationMs, std::function<LONGLONG()> clock = CaptureClockNow);
        int SubmitScreen(std::unique_ptr<MonitorCaptureResult> frame, LONGLONG qpcTime);
        int SubmitCamera(std::unique_ptr<CameraFrameResult> frame, LONGLONG qpcTime);
        int SubmitAudio(std::uint64_t devicePosition, LONGLONG qpcTime, std::vector<std::uint8_t> const& pcm);
        int WaitStart(HANDLE cancellation);
        int WaitFrameTime(LONGLONG time, HANDLE cancellation);
        int ReadFrame(LONGLONG time, LONGLONG duration, RecordingFramePacket& packet, HANDLE cancellation);
        void Fail(int error) noexcept;
        void Close() noexcept;
        OutputLayout const Layout;

    private:
        int SubmitVideoTime(RecordingSourceKind kind, LONGLONG qpcTime, LONGLONG& relative);
        int ErrorLocked(HANDLE cancellation);
        std::function<LONGLONG()> clock_;
        BoundedRecordingBuffer buffer_;
        std::mutex mutex_;
        std::condition_variable changed_;
        int ready_ = 0, error_ = PingCaptureSuccess;
        bool armed_ = false;
        LONGLONG start_ = -1, lastScreen_ = -1, lastCamera_ = -1;
        std::uint64_t audioBase_ = 0, audioNext_ = 0, targetSamples_;
    };

    class IRecordingSource
    {
    public:
        virtual ~IRecordingSource() = default;
        virtual void Start() = 0;
        virtual void RequestStop() noexcept = 0;
        virtual void WaitStopped() noexcept = 0;
    };

    class RecordingSourceWorker : public IRecordingSource
    {
    public:
        explicit RecordingSourceWorker(std::shared_ptr<RecordingSourceState> state);
        ~RecordingSourceWorker();
        void Start() override;
        void RequestStop() noexcept override;
        void WaitStopped() noexcept override;
    protected:
        virtual int Run(HANDLE stopEvent) = 0;
        std::shared_ptr<RecordingSourceState> const State;
    private:
        HANDLE stopEvent_ = nullptr;
        std::thread worker_;
    };

    class LiveRecordingProvider final : public IRecordingFrameProvider
    {
    public:
        LiveRecordingProvider(std::shared_ptr<RecordingSourceState> state, std::vector<std::unique_ptr<IRecordingSource>> sources);
        ~LiveRecordingProvider();
        int ReadFrame(LONGLONG time, LONGLONG duration, RecordingFramePacket& packet, HANDLE cancellation) override;
        void Stop() noexcept override;
    private:
        std::shared_ptr<RecordingSourceState> state_;
        std::vector<std::unique_ptr<IRecordingSource>> sources_;
        bool started_ = false, stopped_ = false;
    };

    int CreateLiveRecordingProvider(int monitor, double faceRatio, CaptureViewport viewport, int durationMs,
        OutputLayout& layout, std::unique_ptr<IRecordingFrameProvider>& provider);
}
