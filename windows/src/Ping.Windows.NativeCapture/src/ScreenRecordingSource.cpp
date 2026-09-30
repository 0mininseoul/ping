#include "NativeRecordingSources.h"
#include "CaptureCallbackGate.h"
#include "CapturePixelView.h"
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <dxgi.h>
#include <chrono>

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
        struct Apartment { Apartment() { init_apartment(apartment_type::multi_threaded); } ~Apartment() { uninit_apartment(); } };
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
            std::shared_ptr<RecordingSourceState> Pipeline;
            ComPtr<ID3D11Device> Device;
            ComPtr<ID3D11DeviceContext> Context;
            ComPtr<ID3D11Texture2D> Staging;
            CaptureSize ExpectedSize;
            CaptureViewport Viewport;
            LONGLONG LastFrame = -1;
        };
        void ReadFrame(std::shared_ptr<ScreenCallbackState> const& state, Direct3D11CaptureFramePool const& sender)
        {
            auto lease = state->Gate.Enter();
            if (!lease) return;
            try
            {
                auto frame = sender.TryGetNextFrame();
                if (!frame) return;
                auto timestamp = frame.SystemRelativeTime().count();
                if (state->LastFrame >= 0 && timestamp - state->LastFrame < 10'000'000 / 30 - 5'000) return;
                state->LastFrame = timestamp;
                auto size = frame.ContentSize();
                if (size.Width != state->ExpectedSize.Width || size.Height != state->ExpectedSize.Height)
                { state->Pipeline->Fail(PingCaptureCaptureFailure); return; }
                ComPtr<ID3D11Texture2D> captured;
                auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
                check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), reinterpret_cast<void**>(captured.GetAddressOf())));
                D3D11_TEXTURE2D_DESC desc{}; captured->GetDesc(&desc);
                if (desc.Width < static_cast<UINT>(size.Width) || desc.Height < static_cast<UINT>(size.Height)
                    || desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM || desc.SampleDesc.Count != 1)
                { state->Pipeline->Fail(PingCaptureCaptureFailure); return; }
                desc.BindFlags = 0; desc.MiscFlags = 0; desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ; desc.Usage = D3D11_USAGE_STAGING;
                MappedTexture staging{state->Context, nullptr};
                if (!state->Staging) check_hresult(state->Device->CreateTexture2D(&desc, nullptr, &state->Staging));
                staging.Texture = state->Staging;
                state->Context->CopyResource(staging.Texture.Get(), captured.Get());
                D3D11_MAPPED_SUBRESOURCE mapped{};
                check_hresult(state->Context->Map(staging.Texture.Get(), 0, D3D11_MAP_READ, 0, &mapped)); staging.Mapped = true;
                if (mapped.RowPitch > INT32_MAX) { state->Pipeline->Fail(PingCaptureCaptureFailure); return; }
                auto output = std::make_unique<MonitorCaptureResult>();
                output->SourceSize = {state->Pipeline->Layout.Width, state->Pipeline->Layout.Height};
                CapturePixelView view{static_cast<std::uint8_t const*>(mapped.pData), static_cast<size_t>(mapped.RowPitch) * desc.Height,
                    0, static_cast<std::int32_t>(mapped.RowPitch), {size.Width, size.Height}};
                auto result = ResizeCapturePixels(view, ComputeCaptureCrop(view.SourceSize, state->Viewport), output->SourceSize,
                    output->BgraPixels, output->RowPitch);
                if (result != PingCaptureSuccess) { state->Pipeline->Fail(result); return; }
                auto submitted = state->Pipeline->SubmitScreen(std::move(output), timestamp);
                if (submitted != PingCaptureSuccess) state->Pipeline->Fail(submitted);
            }
            catch (hresult_error const& error) { state->Pipeline->Fail(error.code() == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureCaptureFailure); }
            catch (...) { state->Pipeline->Fail(PingCaptureCaptureFailure); }
        }
        struct ScreenSession
        {
            std::shared_ptr<ScreenCallbackState> State;
            Direct3D11CaptureFramePool Pool{nullptr};
            GraphicsCaptureSession Session{nullptr};
            event_token Token{};
            bool Subscribed = false;
            ~ScreenSession()
            {
                State->Gate.CloseAndDrain();
                try { if (Subscribed) Pool.FrameArrived(Token); } catch (...) {}
                try { if (Session) Session.Close(); } catch (...) {}
                try { if (Pool) Pool.Close(); } catch (...) {}
            }
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
                    if (!GraphicsCaptureSession::IsSupported()) return PingCaptureUnsupportedOs;
                    auto monitor = SelectMonitor(monitor_); if (!monitor) return PingCaptureNoMonitor;
                    auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
                    GraphicsCaptureItem item{nullptr};
                    check_hresult(interop->CreateForMonitor(monitor, guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(), put_abi(item)));
                    auto size = item.Size();
                    if (size.Width != size_.Width || size.Height != size_.Height) return PingCaptureCaptureFailure;
                    auto callback = std::make_shared<ScreenCallbackState>();
                    callback->Pipeline = State; callback->ExpectedSize = size_; callback->Viewport = viewport_;
                    auto hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                        nullptr, 0, D3D11_SDK_VERSION, &callback->Device, nullptr, &callback->Context);
                    if (FAILED(hr)) hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                        nullptr, 0, D3D11_SDK_VERSION, &callback->Device, nullptr, &callback->Context);
                    check_hresult(hr);
                    ComPtr<IDXGIDevice> dxgi; check_hresult(callback->Device.As(&dxgi));
                    com_ptr<::IInspectable> inspectable;
                    check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi.Get(), inspectable.put()));
                    ScreenSession owned{callback};
                    owned.Pool = Direct3D11CaptureFramePool::CreateFreeThreaded(inspectable.as<IDirect3DDevice>(),
                        DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
                    owned.Session = owned.Pool.CreateCaptureSession(item);
                    if (auto paced = owned.Session.try_as<IGraphicsCaptureSession5>()) paced.MinUpdateInterval(std::chrono::milliseconds(33));
                    owned.Token = owned.Pool.FrameArrived([callback](auto const& pool, auto const&) { ReadFrame(callback, pool); });
                    owned.Subscribed = true;
                    owned.Session.StartCapture();
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
}
