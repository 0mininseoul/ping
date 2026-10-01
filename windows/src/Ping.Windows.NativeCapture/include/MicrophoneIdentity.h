#pragma once
#include "PingCaptureEngine.h"
#include <mmdeviceapi.h>

namespace Ping::Windows::NativeCapture
{
    HRESULT GetDefaultMicrophoneEndpoint(IMMDevice** endpoint);
}
