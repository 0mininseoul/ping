#include "CameraReaderSession.h"
#include "CameraSampleNormalizer.h"
#include "CaptureCallbackGate.h"
#include "LiveRecording.h"
#include <mfapi.h>
#include <mferror.h>
#include <wrl/implements.h>
#include <mutex>
#include <stdexcept>

using Microsoft::WRL::ComPtr;

namespace Ping::Windows::NativeCapture
{
    namespace
    {
        constexpr DWORD VideoStream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
        constexpr DWORD AllStreams = static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS);
        struct ReaderState
        {
            CaptureCallbackGate Gate;
            ComPtr<IMFSourceReader> Reader;
            CameraSampleState Samples;
            CameraReaderSession::Publisher Publish;
            CameraReaderSession::Failure Failure;
            int FaceDiameter;
            HANDLE Flushed = CreateEventW(nullptr, TRUE, FALSE, nullptr);
            bool Failed = false;
            ~ReaderState() { if (Flushed) CloseHandle(Flushed); }
            void Fail(int error) noexcept
            {
                if (Failed) return;
                Failed = true;
                try { if (Failure) Failure(error); } catch (...) {}
            }
        };
        class ReaderCallback final : public Microsoft::WRL::RuntimeClass<Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IMFSourceReaderCallback>
        {
        public:
            explicit ReaderCallback(std::shared_ptr<ReaderState> state) : state_(std::move(state)) {}
            STDMETHODIMP OnReadSample(HRESULT status, DWORD, DWORD flags, LONGLONG timestamp, IMFSample* sample) override
            {
                auto lease = state_->Gate.Enter(); if (!lease || state_->Failed) return S_OK;
                try
                {
                    if (FAILED(status) || (flags & (MF_SOURCE_READERF_ENDOFSTREAM | MF_SOURCE_READERF_ERROR)))
                    { state_->Fail(status == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera); return S_OK; }
                    if (sample)
                    {
                        ComPtr<IMFMediaType> type;
                        if (FAILED(state_->Reader->GetCurrentMediaType(VideoStream, &type)))
                        { state_->Fail(PingCaptureNoCamera); return S_OK; }
                        std::unique_ptr<CameraFrameResult> frame; LONGLONG qpc = 0;
                        auto result = NormalizeCameraSample(type.Get(), sample, state_->FaceDiameter, timestamp,
                            CaptureClockNow(), state_->Samples, frame, qpc);
                        if (result == PingCaptureSuccess) result = state_->Publish(std::move(frame), qpc);
                        if (result != PingCaptureSuccess) { state_->Fail(result); return S_OK; }
                    }
                    auto hr = state_->Reader->ReadSample(VideoStream, 0, nullptr, nullptr, nullptr, nullptr);
                    if (FAILED(hr)) state_->Fail(hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera);
                }
                catch (...) { state_->Fail(PingCaptureNoCamera); }
                return S_OK;
            }
            STDMETHODIMP OnEvent(DWORD, IMFMediaEvent* event) override
            {
                auto lease = state_->Gate.Enter(); if (!lease || !event) return S_OK;
                HRESULT status = S_OK;
                if (SUCCEEDED(event->GetStatus(&status)) && FAILED(status))
                    state_->Fail(status == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera);
                return S_OK;
            }
            STDMETHODIMP OnFlush(DWORD stream) override
            {
                auto lease = state_->Gate.Enter();
                if (stream == AllStreams) SetEvent(state_->Flushed);
                return S_OK;
            }
        private: std::shared_ptr<ReaderState> state_;
        };
    }

    struct CameraReaderSession::Impl
    {
        std::shared_ptr<ReaderState> State = std::make_shared<ReaderState>();
        ComPtr<ReaderCallback> Callback;
        std::mutex Lifecycle;
        HRESULT Initialized = E_UNEXPECTED;
        bool Attempted = false, ReadAttempted = false, Closed = false;
    };
    CameraReaderSession::CameraReaderSession(int diameter, Publisher publish, Failure fail) : impl_(std::make_unique<Impl>())
    {
        if (diameter <= 0 || diameter > 540 || !publish || !fail) throw std::invalid_argument("Invalid camera session contract");
        if (!impl_->State->Flushed) throw std::runtime_error("Camera flush event unavailable");
        impl_->State->FaceDiameter = diameter; impl_->State->Publish = std::move(publish); impl_->State->Failure = std::move(fail);
    }
    CameraReaderSession::~CameraReaderSession() { Close(); }
    HRESULT CameraReaderSession::InitializeReader(ReaderFactory const& create)
    {
        std::lock_guard lock(impl_->Lifecycle);
        if (impl_->Attempted || impl_->Closed || !create) return E_UNEXPECTED;
        impl_->Attempted = true;
        impl_->Callback = Microsoft::WRL::Make<ReaderCallback>(impl_->State);
        ComPtr<IMFAttributes> attributes;
        auto hr = MFCreateAttributes(&attributes, 2);
        if (SUCCEEDED(hr)) hr = attributes->SetUnknown(MF_SOURCE_READER_ASYNC_CALLBACK, impl_->Callback.Get());
        if (SUCCEEDED(hr)) hr = attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
        if (SUCCEEDED(hr)) hr = create(attributes.Get(), &impl_->State->Reader);
        if (SUCCEEDED(hr) && !impl_->State->Reader) hr = E_UNEXPECTED;
        if (SUCCEEDED(hr)) hr = impl_->State->Reader->SetStreamSelection(AllStreams, FALSE);
        if (SUCCEEDED(hr)) hr = impl_->State->Reader->SetStreamSelection(VideoStream, TRUE);
        ComPtr<IMFMediaType> desired;
        if (SUCCEEDED(hr)) hr = MFCreateMediaType(&desired);
        if (SUCCEEDED(hr)) hr = desired->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = desired->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
        if (SUCCEEDED(hr)) hr = impl_->State->Reader->SetCurrentMediaType(VideoStream, nullptr, desired.Get());
        impl_->Initialized = hr;
        return hr;
    }
    HRESULT CameraReaderSession::Start()
    {
        std::lock_guard lock(impl_->Lifecycle);
        if (impl_->Closed || impl_->ReadAttempted || FAILED(impl_->Initialized)) return E_UNEXPECTED;
        impl_->ReadAttempted = true;
        return impl_->State->Reader->ReadSample(VideoStream, 0, nullptr, nullptr, nullptr, nullptr);
    }
    void CameraReaderSession::Close() noexcept
    {
        std::lock_guard lock(impl_->Lifecycle);
        if (impl_->Closed) return;
        impl_->Closed = true;
        auto state = impl_->State;
        state->Gate.CloseAndDrain();
        if (impl_->ReadAttempted && state->Reader)
        {
            ResetEvent(state->Flushed);
            if (SUCCEEDED(state->Reader->Flush(AllStreams))) WaitForSingleObject(state->Flushed, INFINITE);
        }
        state->Gate.CloseAndDrain();
        state->Reader.Reset(); impl_->Callback.Reset();
        state->Publish = {}; state->Failure = {};
    }
}
