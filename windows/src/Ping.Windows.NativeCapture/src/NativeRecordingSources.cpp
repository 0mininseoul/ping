#include "NativeRecordingSources.h"

namespace Ping::Windows::NativeCapture
{
    int CreateLiveRecordingProvider(int monitor, double faceRatio, CaptureViewport viewport, int durationMs,
        OutputLayout& layout, std::unique_ptr<IRecordingFrameProvider>& provider)
    {
        CaptureSize size{};
        auto result = GetCaptureMonitorSize(monitor, size);
        if (result != PingCaptureSuccess) return result;
        layout = CreateScreenFaceLayout(size, faceRatio, 540);
        auto state = std::make_shared<RecordingSourceState>(layout, durationMs);
        std::vector<std::unique_ptr<IRecordingSource>> sources;
        sources.push_back(MakeScreenRecordingSource(state, monitor, size, viewport));
        sources.push_back(MakeCameraRecordingSource(state));
        sources.push_back(MakeAudioRecordingSource(state));
        provider = std::make_unique<LiveRecordingProvider>(state, std::move(sources));
        return PingCaptureSuccess;
    }
}
