#include "NativeRecordingSources.h"
#include "CaptureCallbackGate.h"
#include "CapturePixelView.h"
#include "ScreenFrameContract.h"
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <dxgi.h>
#include <chrono>
#include <functional>

using Microsoft::WRL::ComPtr;
using namespace winrt;
using namespace winrt::Windows::Graphics::Capture;
using namespace winrt::Windows::Graphics::DirectX;
using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

namespace Ping::Windows::NativeCapture
{
    namespace
    {
        BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data)
        { reinterpret_cast<std::vector<HMONITOR>*>(data)->push_back(monitor); return TRUE; }
        HMONITOR SelectMonitor(int index)
        {
            if (index < 0) return MonitorFromPoint(POINT{}, MONITOR_DEFAULTTOPRIMARY);
            std::vector<HMONITOR> monitors;
            EnumDisplayMonitors(nullptr, nullptr, CollectMonitor, reinterpret_cast<LPARAM>(&monitors));
            return static_cast<size_t>(index) < monitors.size() ? monitors[index] : nullptr;
        }
        struct Apartment
        {
            bool Owned = false;
            Apartment()
            {
                try { init_apartment(apartment_type::multi_threaded); Owned = true; }
                catch (hresult_error const& error) { if (error.code() != RPC_E_CHANGED_MODE) throw; }
            }
            ~Apartment() { if (Owned) uninit_apartment(); }
        };
        struct MappedTexture
        {
            ComPtr<ID3D11DeviceContext> Context;
            ComPtr<ID3D11Texture2D> Texture;
            bool Mapped = false;
            ~MappedTexture() { if (Mapped) Context->Unmap(Texture.Get(), 0); }
        };
        struct ScreenCallbackState
        {
            CaptureCallbackGate Gate;
            std::function<void(std::unique_ptr<MonitorCaptureResult>, LONGLONG)> Publish;
            std::function<void(int)> Fail;
            ComPtr<ID3D11Device> Device;
            ComPtr<ID3D11DeviceContext> Context;
            ComPtr<ID3D11Texture2D> Staging;
            CaptureSize ExpectedSize;
            CaptureSize OutputSize;
            CaptureViewport Viewport;
            LONGLONG LastFrame = -1;
            bool SingleFrame = false;
        };
        void ReadFrame(std::shared_ptr<ScreenCallbackState> const& state, Direct3D11CaptureFramePool const& sender)
        {
            auto lease = state->Gate.Enter();
            if (!lease) return;
            try
            {
                auto frame = sender.TryGetNextFrame();
                if (!frame) return;
                if (state->SingleFrame && state->LastFrame >= 0) return;
                auto timestamp = frame.SystemRelativeTime().count();
                if (state->LastFrame >= 0 && timestamp - state->LastFrame < 10'000'000 / 30 - 5'000) return;
                state->LastFrame = timestamp;
                auto size = frame.ContentSize();
                ComPtr<ID3D11Texture2D> captured;
                auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
                check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void**>(captured.GetAddressOf())));
                D3D11_TEXTURE2D_DESC desc{}; captured->GetDesc(&desc);
                if (!ValidateScreenTexture(desc, {size.Width, size.Height}, state->ExpectedSize))
                { state->Fail(PingCaptureCaptureFailure); return; }
                desc.BindFlags = 0; desc.MiscFlags = 0; desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ; desc.Usage = D3D11_USAGE_STAGING;
                MappedTexture staging{state->Context, nullptr};
                if (state->Staging)
                {
                    D3D11_TEXTURE2D_DESC cached{}; state->Staging->GetDesc(&cached);
                    if (!SameScreenTextureStorage(cached, desc)) state->Staging.Reset();
                }
                if (!state->Staging) check_hresult(state->Device->CreateTexture2D(&desc, nullptr, &state->Staging));
                staging.Texture = state->Staging;
                state->Context->CopyResource(staging.Texture.Get(), captured.Get());
                D3D11_MAPPED_SUBRESOURCE mapped{};
                check_hresult(state->Context->Map(staging.Texture.Get(), 0, D3D11_MAP_READ, 0, &mapped)); staging.Mapped = true;
                if (mapped.RowPitch > INT32_MAX) { state->Fail(PingCaptureCaptureFailure); return; }
                auto output = std::make_unique<MonitorCaptureResult>();
                output->SourceSize = state->OutputSize;
                CapturePixelView view{static_cast<std::uint8_t const*>(mapped.pData), static_cast<size_t>(mapped.RowPitch) * desc.Height,
                    0, static_cast<std::int32_t>(mapped.RowPitch), {size.Width, size.Height}};
                auto result = ResizeCapturePixels(view, ComputeCaptureCrop(view.SourceSize, state->Viewport), output->SourceSize,
                    output->BgraPixels, output->RowPitch);
                if (result != PingCaptureSuccess) { state->Fail(result); return; }
                state->Publish(std::move(output), timestamp);
            }
            catch (hresult_error const& error) { state->Fail(error.code() == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureCaptureFailure); }
            catch (...) { state->Fail(PingCaptureCaptureFailure); }
        }
        struct ScreenSession
        {
            std::shared_ptr<ScreenCallbackState> State;
            Direct3D11CaptureFramePool Pool{nullptr};
            GraphicsCaptureSession Session{nullptr};
            event_token Token{};
            bool Subscribed = false;
            void Close() noexcept
            {
                State->Gate.CloseAndDrain();
                try { if (Subscribed) Pool.FrameArrived(Token); } catch (...) {}
                Subscribed = false;
                try { if (Session) Session.Close(); } catch (...) {}
                Session = nullptr;
                try { if (Pool) Pool.Close(); } catch (...) {}
                Pool = nullptr;
            }
            ~ScreenSession() { Close(); }
        };
        int StartScreenSession(ScreenSession& owned, int monitorIndex)
        {
            if (!GraphicsCaptureSession::IsSupported()) return PingCaptureUnsupportedOs;
            auto monitor = SelectMonitor(monitorIndex); if (!monitor) return PingCaptureNoMonitor;
            auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
            GraphicsCaptureItem item{nullptr};
            check_hresult(interop->CreateForMonitor(monitor, guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(), put_abi(item)));
            auto size = item.Size();
            auto callback = owned.State;
            if (size.Width != callback->ExpectedSize.Width || size.Height != callback->ExpectedSize.Height) return PingCaptureCaptureFailure;
            auto hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                nullptr, 0, D3D11_SDK_VERSION, &callback->Device, nullptr, &callback->Context);
            if (FAILED(hr)) hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                nullptr, 0, D3D11_SDK_VERSION, &callback->Device, nullptr, &callback->Context);
            check_hresult(hr);
            ComPtr<IDXGIDevice> dxgi; check_hresult(callback->Device.As(&dxgi));
            com_ptr<::IInspectable> inspectable;
            check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.Get(), inspectable.put()));
            owned.Pool = Direct3D11CaptureFramePool::CreateFreeThreaded(inspectable.as<IDirect3DDevice>(),
                DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
            owned.Session = owned.Pool.CreateCaptureSession(item);
            if (auto paced = owned.Session.try_as<IGraphicsCaptureSession5>()) paced.MinUpdateInterval(std::chrono::milliseconds(33));
            owned.Token = owned.Pool.FrameArrived([callback](auto const& pool, auto const&) { ReadFrame(callback, pool); });
            owned.Subscribed = true;
            owned.Session.StartCapture();
            return PingCaptureSuccess;
        }

        struct SnapshotResult
        {
            HANDLE Ready = CreateEventW(nullptr, TRUE, FALSE, nullptr);
            std::unique_ptr<MonitorCaptureResult> Frame;
            int Error = PingCaptureCaptureFailure;
            ~SnapshotResult() { if (Ready) CloseHandle(Ready); }
        };
        class ScreenSource final : public RecordingSourceWorker
        {
        public:
            ScreenSource(std::shared_ptr<RecordingSourceState> state, int monitor, CaptureSize size, CaptureViewport viewport)
                : RecordingSourceWorker(std::move(state)), monitor_(monitor), size_(size), viewport_(viewport) {}
            int Run(HANDLE stop) override
            {
                try
                {
                    Apartment apartment;
                    auto callback = std::make_shared<ScreenCallbackState>();
                    callback->ExpectedSize = size_; callback->Viewport = viewport_;
                    callback->OutputSize = {State->Layout.Width, State->Layout.Height};
                    callback->Publish = [pipeline = State](auto frame, LONGLONG timestamp)
                    {
                        auto result = pipeline->SubmitScreen(std::move(frame), timestamp);
                        if (result != PingCaptureSuccess) pipeline->Fail(result);
                    };
                    callback->Fail = [pipeline = State](int error) { pipeline->Fail(error); };
                    ScreenSession owned{callback};
                    auto result = StartScreenSession(owned, monitor_);
                    if (result != PingCaptureSuccess) return result;
                    WaitForSingleObject(stop, INFINITE);
                    return PingCaptureSuccess;
                }
                catch (hresult_error const& error) { return error.code() == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureCaptureFailure; }
            }
        private: int monitor_; CaptureSize size_; CaptureViewport viewport_;
        };
    }
    int GetCaptureMonitorSize(int index, CaptureSize& size)
    {
        auto monitor = SelectMonitor(index); if (!monitor) return PingCaptureNoMonitor;
        MONITORINFO info{}; info.cbSize = sizeof(info);
        if (!GetMonitorInfoW(monitor, &info)) return PingCaptureNoMonitor;
        size = {info.rcMonitor.right - info.rcMonitor.left, info.rcMonitor.bottom - info.rcMonitor.top};
        return size.Width > 0 && size.Height > 0 ? PingCaptureSuccess : PingCaptureNoMonitor;
    }
    std::unique_ptr<IRecordingSource> MakeScreenRecordingSource(std::shared_ptr<RecordingSourceState> state,
        int monitor, CaptureSize size, CaptureViewport viewport)
    { return std::make_unique<ScreenSource>(std::move(state), monitor, size, viewport); }

    int CaptureMonitorPreviewFrame(int monitor, CaptureViewport viewport, HANDLE cancellation, MonitorCaptureResult& result)
    {
        result = {};
        try
        {
            if (cancellation && WaitForSingleObject(cancellation, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;
            Apartment apartment;
            CaptureSize size{};
            auto monitorResult = GetCaptureMonitorSize(monitor, size);
            if (monitorResult != PingCaptureSuccess) return monitorResult;
            auto layout = CreateScreenFaceLayout(size, .32, 1920);
            auto snapshot = std::make_shared<SnapshotResult>();
            if (!snapshot->Ready) return PingCaptureCaptureFailure;
            auto callback = std::make_shared<ScreenCallbackState>();
            callback->ExpectedSize = size; callback->OutputSize = {layout.Width, layout.Height};
            callback->Viewport = viewport; callback->SingleFrame = true;
            callback->Publish = [snapshot](auto frame, LONGLONG)
            { snapshot->Frame = std::move(frame); snapshot->Error = PingCaptureSuccess; SetEvent(snapshot->Ready); };
            callback->Fail = [snapshot](int error) { snapshot->Error = error; SetEvent(snapshot->Ready); };
            ScreenSession owned{callback};
            auto started = StartScreenSession(owned, monitor);
            if (started != PingCaptureSuccess) return started;
            HANDLE events[]{snapshot->Ready, cancellation};
            auto wait = WaitForMultipleObjects(cancellation ? 2 : 1, events, FALSE, 3000);
            owned.Close();
            if (wait == WAIT_OBJECT_0 + 1 || (cancellation && WaitForSingleObject(cancellation, 0) == WAIT_OBJECT_0))
                return PingCaptureCancelled;
            if (wait != WAIT_OBJECT_0) return PingCaptureCaptureFailure;
            if (snapshot->Error != PingCaptureSuccess) return snapshot->Error;
            if (!snapshot->Frame) return PingCaptureCaptureFailure;
            result = std::move(*snapshot->Frame);
            return PingCaptureSuccess;
        }
        catch (hresult_error const& error) { return error.code() == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureCaptureFailure; }
        catch (...) { return PingCaptureCaptureFailure; }
    }
    int CaptureOneMonitorFrame(int monitor, MonitorCaptureResult& result)
    { return CaptureMonitorPreviewFrame(monitor, {}, nullptr, result); }
}
