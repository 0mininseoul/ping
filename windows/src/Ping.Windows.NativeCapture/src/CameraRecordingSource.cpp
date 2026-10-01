#include "NativeRecordingSources.h"
#include "CaptureCallbackGate.h"
#include "CameraSampleNormalizer.h"
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <winrt/base.h>
#include <wrl/implements.h>
#include <algorithm>
#include <optional>

using Microsoft::WRL::ComPtr;

namespace Ping::Windows::NativeCapture
{
    namespace
    {
        struct Apartment { Apartment() { winrt::init_apartment(winrt::apartment_type::multi_threaded); } ~Apartment() { winrt::uninit_apartment(); } };
        struct Foundation { bool Started = false; ~Foundation() { if (Started) MFShutdown(); } };
        struct CameraCallbackState
        {
            CaptureCallbackGate Gate;
            std::shared_ptr<RecordingSourceState> Pipeline;
            ComPtr<IMFSourceReader> Reader;
            HANDLE Flushed = CreateEventW(nullptr, TRUE, FALSE, nullptr);
            CameraSampleState Samples;
            ~CameraCallbackState() { if (Flushed) CloseHandle(Flushed); }
        };
        int ReadCameraPixels(std::shared_ptr<CameraCallbackState> const& state, IMFSample* sample, LONGLONG timestamp)
        {
            ComPtr<IMFMediaType> type;
            if (FAILED(state->Reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &type))) return PingCaptureNoCamera;
            std::unique_ptr<CameraFrameResult> frame;
            LONGLONG qpc = 0;
            auto result = NormalizeCameraSample(type.Get(), sample, state->Pipeline->Layout.FaceDiameter, timestamp,
                CaptureClockNow(), state->Samples, frame, qpc);
            return result == PingCaptureSuccess ? state->Pipeline->SubmitCamera(std::move(frame), qpc) : result;
        }
        class CameraCallback final : public Microsoft::WRL::RuntimeClass<Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IMFSourceReaderCallback>
        {
        public:
            explicit CameraCallback(std::shared_ptr<CameraCallbackState> state) : state_(std::move(state)) {}
            STDMETHODIMP OnReadSample(HRESULT status, DWORD, DWORD flags, LONGLONG timestamp, IMFSample* sample) override
            {
                auto lease = state_->Gate.Enter(); if (!lease) return S_OK;
                try
                {
                    if (FAILED(status) || (flags & (MF_SOURCE_READERF_ENDOFSTREAM | MF_SOURCE_READERF_ERROR)))
                    { state_->Pipeline->Fail(status == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera); return S_OK; }
                    if (sample)
                    {
                        auto result = ReadCameraPixels(state_, sample, timestamp);
                        if (result != PingCaptureSuccess) { state_->Pipeline->Fail(result); return S_OK; }
                    }
                    auto hr = state_->Reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, nullptr, nullptr, nullptr);
                    if (FAILED(hr)) state_->Pipeline->Fail(PingCaptureNoCamera);
                }
                catch (...) { state_->Pipeline->Fail(PingCaptureNoCamera); }
                return S_OK;
            }
            STDMETHODIMP OnEvent(DWORD, IMFMediaEvent* event) override
            {
                auto lease = state_->Gate.Enter(); if (!lease || !event) return S_OK;
                HRESULT status = S_OK;
                if (SUCCEEDED(event->GetStatus(&status)) && FAILED(status)) state_->Pipeline->Fail(PingCaptureNoCamera);
                return S_OK;
            }
            STDMETHODIMP OnFlush(DWORD) override { auto lease = state_->Gate.Enter(); SetEvent(state_->Flushed); return S_OK; }
        private: std::shared_ptr<CameraCallbackState> state_;
        };
        struct CameraSession
        {
            std::shared_ptr<CameraCallbackState> State;
            ComPtr<IMFMediaSource> Source;
            ComPtr<CameraCallback> Callback;
            bool Started = false;
            ~CameraSession()
            {
                State->Gate.CloseAndDrain();
                if (Started && State->Reader && SUCCEEDED(State->Reader->Flush(MF_SOURCE_READER_ALL_STREAMS)))
                    WaitForSingleObject(State->Flushed, INFINITE);
                State->Gate.CloseAndDrain();
                if (Source) Source->Shutdown();
                State->Reader.Reset(); Source.Reset(); Callback.Reset();
            }
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
                    auto callbackState = std::make_shared<CameraCallbackState>(); callbackState->Pipeline = State;
                    if (!callbackState->Flushed) return PingCaptureNoCamera;
                    CameraSession owned{callbackState};
                    hr = CreateCamera(device_, &owned.Source);
                    owned.Callback = Microsoft::WRL::Make<CameraCallback>(callbackState);
                    ComPtr<IMFAttributes> attributes;
                    if (SUCCEEDED(hr)) hr = MFCreateAttributes(&attributes, 2);
                    if (SUCCEEDED(hr)) hr = attributes->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, owned.Callback.Get());
                    if (SUCCEEDED(hr)) hr = attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
                    if (SUCCEEDED(hr)) hr = MFCreateSourceReaderFromMediaSource(owned.Source.Get(), attributes.Get(), &callbackState->Reader);
                    ComPtr<IMFMediaType> desired;
                    if (SUCCEEDED(hr)) hr = MFCreateMediaType(&desired);
                    if (SUCCEEDED(hr)) hr = desired->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
                    if (SUCCEEDED(hr)) hr = desired->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
                    if (SUCCEEDED(hr)) hr = callbackState->Reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, desired.Get());
                    if (SUCCEEDED(hr)) hr = callbackState->Reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, nullptr, nullptr, nullptr, nullptr);
                    if (FAILED(hr)) return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
                    owned.Started = true;
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
