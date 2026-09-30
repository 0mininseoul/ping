#pragma once
#include "LiveRecording.h"
#include <string>

namespace Ping::Windows::NativeCapture
{
    int GetCaptureMonitorSize(int monitor, CaptureSize& size);
    std::unique_ptr<IRecordingSource> MakeScreenRecordingSource(std::shared_ptr<RecordingSourceState> state,
        int monitor, CaptureSize sourceSize, CaptureViewport viewport);
    std::unique_ptr<IRecordingSource> MakeCameraRecordingSource(std::shared_ptr<RecordingSourceState> state,
        std::wstring deviceId = {});
    std::unique_ptr<IRecordingSource> MakeAudioRecordingSource(std::shared_ptr<RecordingSourceState> state,
        std::wstring endpointId = {});
}
