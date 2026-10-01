#include "NativeRecordingSources.h"
#include "CameraReaderSession.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <winrt/base.h>
using Microsoft::WRL::ComPtr;

namespace Ping::Windows::NativeCapture
{
    namespace
    {
        struct Apartment { Apartment() { winrt::init_apartment(winrt::apartment_type::multi_threaded); } ~Apartment() { winrt::uninit_apartment(); } };
        struct Foundation { bool Started = false; ~Foundation() { if (Started) MFShutdown(); } };
        struct CameraMediaSource
        {
            ComPtr<IMFMediaSource> Source;
            ~CameraMediaSource() { if (Source) Source->Shutdown(); }
        };
        HRESULT CreateCamera(std::wstring const& deviceId, IMFMediaSource** source)
        {
            ComPtr<IMFAttributes> attributes;
            auto hr = MFCreateAttributes(&attributes, 2);
            if (SUCCEEDED(hr)) hr = attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE, MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
            if (SUCCEEDED(hr) && !deviceId.empty()) hr = attributes->SetString(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK, deviceId.c_str());
            if (FAILED(hr)) return hr;
            if (!deviceId.empty()) return MFCreateDeviceSource(attributes.Get(), source);
            IMFActivate** devices = nullptr; UINT32 count = 0;
            hr = MFEnumDeviceSources(attributes.Get(), &devices, &count);
            if (SUCCEEDED(hr)) hr = count ? devices[0]->ActivateObject(IID_PPV_ARGS(source)) : MF_E_NOT_FOUND;
            for (UINT32 i = 0; i < count; ++i) devices[i]->Release();
            CoTaskMemFree(devices);
            return hr;
        }
        class CameraSource final : public RecordingSourceWorker
        {
        public:
            CameraSource(std::shared_ptr<RecordingSourceState> state, std::wstring device)
                : RecordingSourceWorker(std::move(state)), device_(std::move(device)) {}
            int Run(HANDLE stop) override
            {
                try
                {
                    Apartment apartment;
                    Foundation foundation;
                    auto hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
                    if (FAILED(hr)) return PingCaptureNoCamera;
                    foundation.Started = true;
                    CameraMediaSource source;
                    hr = CreateCamera(device_, &source.Source);
                    if (FAILED(hr)) return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
                    CameraReaderSession reader(State->Layout.FaceDiameter,
                        [pipeline = State](auto frame, LONGLONG qpc) { return pipeline->SubmitCamera(std::move(frame), qpc); },
                        [pipeline = State](int error) { pipeline->Fail(error); });
                    hr = reader.InitializeReader([&source](IMFAttributes* attributes, IMFSourceReader** result)
                        { return MFCreateSourceReaderFromMediaSource(source.Source.Get(), attributes, result); });
                    if (SUCCEEDED(hr)) hr = reader.Start();
                    if (FAILED(hr)) return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
                    WaitForSingleObject(stop, INFINITE);
                    return PingCaptureSuccess;
                }
                catch (winrt::hresult_error const& error) { return error.code() == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera; }
            }
        private: std::wstring device_;
        };
    }
    std::unique_ptr<IRecordingSource> MakeCameraRecordingSource(std::shared_ptr<RecordingSourceState> state, std::wstring device)
    { return std::make_unique<CameraSource>(std::move(state), std::move(device)); }
}
