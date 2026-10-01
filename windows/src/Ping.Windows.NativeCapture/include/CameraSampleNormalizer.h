#pragma once
#include "PingCaptureEngine.h"
#include <mfidl.h>
#include <memory>
#include <optional>

namespace Ping::Windows::NativeCapture
{
    struct CameraSampleState
    {
        std::optional<CaptureSize> InputSize;
        std::optional<LONGLONG> SampleOffset;
        std::optional<LONGLONG> LastTimestamp;
    };

    int NormalizeCameraSample(IMFMediaType* type, IMFSample* sample, int faceDiameter,
        LONGLONG sourceTime, LONGLONG arrivalQpc, CameraSampleState& state,
        std::unique_ptr<CameraFrameResult>& output, LONGLONG& outputQpc);
}
