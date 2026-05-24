#include "PingCaptureEngine.h"

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace Ping::Windows::NativeCapture
{
    int ProbeCameraFrameSource()
    {
        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        IMFActivate** devices = nullptr;
        UINT32 deviceCount = 0;

        ComPtr<IMFAttributes> attributes;
        hr = MFCreateAttributes(&attributes, 1);
        if (SUCCEEDED(hr))
        {
            hr = attributes->SetGUID(
                MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
        }

        if (SUCCEEDED(hr))
        {
            hr = MFEnumDeviceSources(attributes.Get(), &devices, &deviceCount);
        }

        if (FAILED(hr))
        {
            MFShutdown();
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        for (UINT32 index = 0; index < deviceCount; ++index)
        {
            devices[index]->Release();
        }
        CoTaskMemFree(devices);
        MFShutdown();

        return deviceCount > 0 ? PingCaptureSuccess : PingCaptureNoCamera;
    }
}
