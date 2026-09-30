#pragma once
#include "LiveRecording.h"
#include <audioclient.h>

namespace Ping::Windows::NativeCapture
{
    int DrainMicrophonePackets(IAudioCaptureClient& capture, std::shared_ptr<RecordingSourceState> const& state,
        HANDLE stopEvent, bool& firstPacket);
}
