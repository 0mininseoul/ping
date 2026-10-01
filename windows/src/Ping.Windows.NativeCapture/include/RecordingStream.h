#pragma once
#include "PingCaptureEngine.h"
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>

namespace Ping::Windows::NativeCapture
{
    struct RecordingFramePacket
    {
        std::shared_ptr<MonitorCaptureResult const> Screen;
        std::shared_ptr<CameraFrameResult const> Camera;
        std::vector<std::uint8_t> Audio;
    };

    class IRecordingFrameProvider
    {
    public:
        virtual ~IRecordingFrameProvider() = default;
        virtual int ReadFrame(LONGLONG sampleTime, LONGLONG sampleDuration,
            RecordingFramePacket& packet, HANDLE cancellationEvent) = 0;
        // Must stop producers and wait for their callbacks before returning.
        virtual void Stop() noexcept = 0;
    };

    // Frames must be cropped/resized before publication. Timestamps use one recording start.
    class BoundedRecordingBuffer
    {
    public:
        explicit BoundedRecordingBuffer(OutputLayout layout);
        int PublishScreen(std::unique_ptr<MonitorCaptureResult> frame, LONGLONG timestamp);
        int PublishCamera(std::unique_ptr<CameraFrameResult> frame, LONGLONG timestamp);
        int PublishAudio(std::uint64_t firstSample, std::vector<std::uint8_t> const& pcm);
        int ReadFrame(LONGLONG sampleTime, LONGLONG sampleDuration,
            RecordingFramePacket& packet, HANDLE cancellationEvent, int timeoutMs = 2000);
        void Fail(int error) noexcept;
        void Close() noexcept;
        size_t RetainedBytes() const noexcept;

    private:
        int FailLocked(int error) noexcept;
        OutputLayout layout_;
        mutable std::mutex mutex_;
        std::condition_variable changed_;
        std::deque<std::pair<std::shared_ptr<MonitorCaptureResult const>, LONGLONG>> screens_;
        std::deque<std::pair<std::shared_ptr<CameraFrameResult const>, LONGLONG>> cameras_;
        LONGLONG screenTime_ = -1, cameraTime_ = -1;
        std::vector<std::uint8_t> audio_;
        size_t audioHead_ = 0, audioSize_ = 0;
        std::uint64_t publishedSamples_ = 0, consumedSamples_ = 0;
        int error_ = PingCaptureSuccess;
    };

    int WriteScreenFaceMp4Stream(const wchar_t* outputPath, OutputLayout const& layout,
        IRecordingFrameProvider& provider, int durationMs, CaptureViewport viewport = {}, HANDLE cancellationEvent = nullptr,
        PingCapturePreviewCallback preview = nullptr, void* previewContext = nullptr);
}
