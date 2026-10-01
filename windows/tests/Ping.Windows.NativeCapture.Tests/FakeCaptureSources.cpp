#include "PingCaptureEngine.h"
#include "LiveRecording.h"
#include "MicrophoneIdentity.h"
#include <chrono>
#include <cstring>
#include <cmath>
#include <atomic>

std::atomic<int> FixtureSourceStarts{0};
std::atomic<int> FixtureLiveMode{0}, FixtureLiveStarted{0}, FixtureLiveDrained{0}, FixtureLegacyStarts{0}, FixtureDrainEntered{0};
std::atomic<LONGLONG> FixtureAudioDrift{0};
HANDLE FixtureDrainRelease = nullptr;
Ping::Windows::NativeCapture::CaptureViewport FixtureViewport{};
std::wstring FixtureCameraDevice;
std::wstring FixtureMicrophoneDevice;
Microsoft::WRL::ComPtr<IMMDevice> FixtureMicrophoneEndpoint;
HRESULT FixtureMicrophoneResult = HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
int FixturePreviewMode = 0;
Ping::Windows::NativeCapture::CaptureViewport FixturePreviewViewport{};
namespace Ping::Windows::NativeCapture
{
    HRESULT GetDefaultMicrophoneEndpoint(IMMDevice** endpoint)
    { if (FAILED(FixtureMicrophoneResult)) return FixtureMicrophoneResult; return FixtureMicrophoneEndpoint.CopyTo(endpoint); }
    int CaptureOneMonitorFrame(int, MonitorCaptureResult&) { ++FixtureSourceStarts; return PingCaptureNoMonitor; }
    int CaptureMonitorPreviewFrame(int, CaptureViewport viewport, HANDLE, MonitorCaptureResult& result)
    {
        ++FixtureSourceStarts; FixturePreviewViewport = viewport;
        if (!FixturePreviewMode) return PingCaptureNoMonitor;
        if (FixturePreviewMode == 2) return PingCaptureCancelled;
        MonitorCaptureResult source{}; source.SourceSize = {8, 4}; source.RowPitch = 32;
        source.BgraPixels.resize(128);
        for (int y = 0; y < 4; ++y) for (int x = 0; x < 8; ++x)
        {
            auto pixel = source.BgraPixels.data() + y * 32 + x * 4;
            pixel[0] = static_cast<std::uint8_t>(x); pixel[1] = static_cast<std::uint8_t>(y); pixel[2] = 0; pixel[3] = 255;
        }
        return CropScreenFrame(source, viewport, {8, 4}, result);
    }
    int CaptureMonitorFrames(int, int, int, std::vector<MonitorCaptureResult>&) { ++FixtureLegacyStarts; ++FixtureSourceStarts; return PingCaptureNoMonitor; }
    int CaptureCameraFrames(int, int, std::vector<CameraFrameResult>&) { ++FixtureLegacyStarts; ++FixtureSourceStarts; return PingCaptureNoCamera; }
    int CaptureMicrophonePcm(int, AudioCaptureResult&) { ++FixtureLegacyStarts; ++FixtureSourceStarts; return PingCaptureNoMicrophone; }

    namespace
    {
        struct DrainScope
        {
            ~DrainScope()
            {
                ++FixtureDrainEntered;
                if (FixtureDrainRelease) WaitForSingleObject(FixtureDrainRelease, INFINITE);
                ++FixtureLiveDrained;
            }
        };
        class FixtureSource final : public RecordingSourceWorker
        {
        public:
            FixtureSource(std::shared_ptr<RecordingSourceState> state, RecordingSourceKind kind, int mode)
                : RecordingSourceWorker(std::move(state)), kind_(kind), mode_(mode) {}
            int Run(HANDLE stop) override
            {
                ++FixtureLiveStarted; DrainScope drain;
                if (mode_ == 2 && kind_ == RecordingSourceKind::Camera) return PingCaptureNoCamera;
                auto base = CaptureClockNow();
                std::uint64_t samples = 0;
                int frame = 0;
                while (WaitForSingleObject(stop, 0) != WAIT_OBJECT_0)
                {
                    int result = PingCaptureSuccess;
                    if (kind_ == RecordingSourceKind::Screen)
                    {
                        auto image = std::make_unique<MonitorCaptureResult>();
                        image->SourceSize = {State->Layout.Width, State->Layout.Height}; image->RowPitch = State->Layout.Width * 4;
                        image->BgraPixels.resize(static_cast<size_t>(image->RowPitch) * image->SourceSize.Height, static_cast<std::uint8_t>(frame++ % 100));
                        result = State->SubmitScreen(std::move(image), CaptureClockNow());
                    }
                    else if (kind_ == RecordingSourceKind::Camera)
                    {
                        auto image = std::make_unique<CameraFrameResult>();
                        image->SourceSize = {State->Layout.FaceDiameter, State->Layout.FaceDiameter}; image->RowPitch = State->Layout.FaceDiameter * 4;
                        image->BgraPixels.resize(static_cast<size_t>(image->RowPitch) * image->SourceSize.Height, 150);
                        result = State->SubmitCamera(std::move(image), CaptureClockNow());
                    }
                    else
                    {
                        std::vector<std::uint8_t> pcm(960);
                        for (size_t i = 0; i < 480; ++i)
                        {
                            auto value = static_cast<std::int16_t>(3000 * std::sin((samples + i) * 440 * 2 * 3.141592653589793 / 48'000));
                            std::memcpy(pcm.data() + i * 2, &value, 2);
                        }
                        auto qpc = base + static_cast<LONGLONG>(samples * 10'000'000 / 48'000);
                        FixtureAudioDrift = CaptureClockNow() - qpc;
                        result = State->SubmitAudio(samples, qpc, pcm);
                        samples += 480;
                    }
                    if (result != PingCaptureSuccess) return result;
                    if (kind_ == RecordingSourceKind::Audio)
                    {
                        auto remaining = base + static_cast<LONGLONG>(samples * 10'000'000 / 48'000) - CaptureClockNow();
                        if (remaining > 0) WaitForSingleObject(stop, static_cast<DWORD>((remaining + 9'999) / 10'000));
                    }
                    else WaitForSingleObject(stop, 33);
                }
                return PingCaptureSuccess;
            }
        private: RecordingSourceKind kind_; int mode_;
        };
    }

    int CreateLiveRecordingProvider(int, double faceRatio, CaptureViewport viewport, int durationMs,
        OutputLayout& layout, std::unique_ptr<IRecordingFrameProvider>& provider, std::wstring const& cameraDeviceId,
        std::wstring const& microphoneEndpointId)
    {
        auto mode = FixtureLiveMode.load();
        if (!mode) return PingCaptureNoMonitor;
        FixtureViewport = viewport;
        FixtureCameraDevice = cameraDeviceId;
        FixtureMicrophoneDevice = microphoneEndpointId;
        layout = CreateScreenFaceLayout({960, 540}, faceRatio, 540);
        auto state = std::make_shared<RecordingSourceState>(layout, durationMs);
        std::vector<std::unique_ptr<IRecordingSource>> sources;
        for (auto kind : {RecordingSourceKind::Screen, RecordingSourceKind::Camera, RecordingSourceKind::Audio})
            sources.push_back(std::make_unique<FixtureSource>(state, kind, mode));
        provider = std::make_unique<LiveRecordingProvider>(state, std::move(sources));
        return PingCaptureSuccess;
    }
}
