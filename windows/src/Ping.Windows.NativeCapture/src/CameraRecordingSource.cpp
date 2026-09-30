#include "NativeRecordingSources.h"
#include "CaptureCallbackGate.h"
#include "CapturePixelView.h"
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
            std::optional<LONGLONG> SampleOffset;
            ~CameraCallbackState() { if (Flushed) CloseHandle(Flushed); }
        };
        struct LockedBuffer
        {
            ComPtr<IMFMediaBuffer> Buffer;
            ComPtr<IMF2DBuffer2> TwoD;
            bool Locked = false;
            ~LockedBuffer() { if (Locked) { if (TwoD) TwoD->Unlock2D(); else Buffer->Unlock(); } }
        };
        int ReadCameraPixels(std::shared_ptr<CameraCallbackState> const& state, IMFSample* sample, LONGLONG timestamp)
        {
            ComPtr<IMFMediaType> type;
            HRESULT hr = state->Reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &type);
            UINT32 width = 0, height = 0;
            if (SUCCEEDED(hr)) hr = MFGetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, &width, &height);
            if (FAILED(hr) || width == 0 || height == 0 || width > 32768 || height > 32768) return PingCaptureNoCamera;
            GUID subtype{};
            if (FAILED(type->GetGUID(MF_MT_SUBTYPE, &subtype)) || subtype != MFVideoFormat_RGB32) return PingCaptureNoCamera;
            LockedBuffer owned;
            hr = sample->ConvertToContiguousBuffer(&owned.Buffer);
            if (FAILED(hr)) return PingCaptureNoCamera;
            BYTE* begin = nullptr; BYTE* scanline = nullptr; DWORD length = 0; LONG stride = 0;
            if (SUCCEEDED(owned.Buffer.As(&owned.TwoD)))
            {
                hr = owned.TwoD->Lock2DSize(MF2DBuffer_LockFlags_Read, &scanline, &stride, &begin, &length);
                if (FAILED(hr)) return PingCaptureNoCamera;
            }
            else
            {
                hr = owned.Buffer->Lock(&begin, nullptr, &length);
                if (FAILED(hr)) return PingCaptureNoCamera;
                UINT32 rawStride = 0;
                if (SUCCEEDED(type->GetUINT32(MF_MT_DEFAULT_STRIDE, &rawStride))) stride = static_cast<LONG>(rawStride);
                else hr = MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, width, &stride);
                scanline = begin;
                if (SUCCEEDED(hr) && stride < 0)
                {
                    auto offset = static_cast<std::uint64_t>(-static_cast<std::int64_t>(stride)) * (height - 1);
                    if (offset >= length) hr = E_FAIL;
                    else scanline += static_cast<size_t>(offset);
                }
            }
            owned.Locked = true;
            if (FAILED(hr) || !begin || !scanline || reinterpret_cast<std::uintptr_t>(scanline) < reinterpret_cast<std::uintptr_t>(begin))
                return PingCaptureNoCamera;
            auto offset = reinterpret_cast<std::uintptr_t>(scanline) - reinterpret_cast<std::uintptr_t>(begin);
            CapturePixelView view{begin, length, offset, stride, {static_cast<int>(width), static_cast<int>(height)}};
            auto side = static_cast<int>(std::min(width, height));
            auto output = std::make_unique<CameraFrameResult>();
            output->SourceSize = {state->Pipeline->Layout.FaceDiameter, state->Pipeline->Layout.FaceDiameter};
            auto result = ResizeCapturePixels(view, {(static_cast<int>(width) - side) / 2, (static_cast<int>(height) - side) / 2, side, side},
                output->SourceSize, output->BgraPixels, output->RowPitch);
            if (result != PingCaptureSuccess) return PingCaptureNoCamera;
            UINT64 qpc = 0;
            if (SUCCEEDED(sample->GetUINT64(MFSampleExtension_DeviceTimestamp, &qpc)) && qpc <= INT64_MAX)
                timestamp = static_cast<LONGLONG>(qpc);
            else
            {
                if (!state->SampleOffset) state->SampleOffset = CaptureClockNow() - timestamp;
                timestamp += *state->SampleOffset;
            }
            return state->Pipeline->SubmitCamera(std::move(output), timestamp);
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
