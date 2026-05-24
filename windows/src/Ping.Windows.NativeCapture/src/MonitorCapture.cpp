#include "PingCaptureEngine.h"

#include <atomic>
#include <vector>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/base.h>

using Microsoft::WRL::ComPtr;

namespace
{
    BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data)
    {
        auto monitors = reinterpret_cast<std::vector<HMONITOR>*>(data);
        monitors->push_back(monitor);
        return TRUE;
    }

    HMONITOR SelectMonitor(int targetMonitorIndex)
    {
        if (targetMonitorIndex < 0)
        {
            POINT origin{};
            return MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
        }

        std::vector<HMONITOR> monitors;
        EnumDisplayMonitors(nullptr, nullptr, CollectMonitor, reinterpret_cast<LPARAM>(&monitors));

        if (targetMonitorIndex >= static_cast<int>(monitors.size()))
        {
            return nullptr;
        }

        return monitors[static_cast<size_t>(targetMonitorIndex)];
    }

    int EnsureApartment()
    {
        try
        {
            winrt::init_apartment(winrt::apartment_type::multi_threaded);
            return PingCaptureSuccess;
        }
        catch (winrt::hresult_error const& error)
        {
            if (error.code() == RPC_E_CHANGED_MODE)
            {
                return PingCaptureSuccess;
            }

            return PingCaptureCaptureFailure;
        }
    }

    HRESULT CreateD3DDevice(ComPtr<ID3D11Device>& device)
    {
        D3D_FEATURE_LEVEL featureLevels[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
        D3D_FEATURE_LEVEL featureLevel{};
        UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;

#if defined(_DEBUG)
        flags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

        HRESULT hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_HARDWARE,
            nullptr,
            flags,
            featureLevels,
            ARRAYSIZE(featureLevels),
            D3D11_SDK_VERSION,
            device.GetAddressOf(),
            &featureLevel,
            nullptr);

#if defined(_DEBUG)
        if (hr == DXGI_ERROR_SDK_COMPONENT_MISSING)
        {
            flags &= ~D3D11_CREATE_DEVICE_DEBUG;
            hr = D3D11CreateDevice(
                nullptr,
                D3D_DRIVER_TYPE_HARDWARE,
                nullptr,
                flags,
                featureLevels,
                ARRAYSIZE(featureLevels),
                D3D11_SDK_VERSION,
                device.ReleaseAndGetAddressOf(),
                &featureLevel,
                nullptr);
        }
#endif

        if (FAILED(hr))
        {
            hr = D3D11CreateDevice(
                nullptr,
                D3D_DRIVER_TYPE_WARP,
                nullptr,
                D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                featureLevels,
                ARRAYSIZE(featureLevels),
                D3D11_SDK_VERSION,
                device.ReleaseAndGetAddressOf(),
                &featureLevel,
                nullptr);
        }

        return hr;
    }
}

namespace Ping::Windows::NativeCapture
{
    int CaptureOneMonitorFrame(int targetMonitorIndex, MonitorCaptureResult& result)
    {
        int apartmentResult = EnsureApartment();
        if (apartmentResult != PingCaptureSuccess)
        {
            return apartmentResult;
        }

        using namespace winrt;
        using namespace Windows::Graphics::Capture;
        using namespace Windows::Graphics::DirectX;
        using namespace Windows::Graphics::DirectX::Direct3D11;

        try
        {
            if (!GraphicsCaptureSession::IsSupported())
            {
                return PingCaptureUnsupportedOs;
            }

            HMONITOR monitor = SelectMonitor(targetMonitorIndex);
            if (monitor == nullptr)
            {
                return PingCaptureNoMonitor;
            }

            auto interop = get_activation_factory<GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
            GraphicsCaptureItem item{ nullptr };
            check_hresult(interop->CreateForMonitor(
                monitor,
                guid_of<ABI::Windows::Graphics::Capture::IGraphicsCaptureItem>(),
                put_abi(item)));

            auto const size = item.Size();
            if (size.Width <= 0 || size.Height <= 0)
            {
                return PingCaptureNoMonitor;
            }

            ComPtr<ID3D11Device> d3dDevice;
            check_hresult(CreateD3DDevice(d3dDevice));

            ComPtr<IDXGIDevice> dxgiDevice;
            check_hresult(d3dDevice.As(&dxgiDevice));

            com_ptr<::IInspectable> inspectableDevice;
            check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.Get(), inspectableDevice.put()));
            auto direct3DDevice = inspectableDevice.as<IDirect3DDevice>();

            auto framePool = Direct3D11CaptureFramePool::CreateFreeThreaded(
                direct3DDevice,
                DirectXPixelFormat::B8G8R8A8UIntNormalized,
                1,
                size);
            auto session = framePool.CreateCaptureSession(item);

            HANDLE frameEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
            if (frameEvent == nullptr)
            {
                return PingCaptureCaptureFailure;
            }

            std::atomic_bool didReceiveFrame = false;
            auto token = framePool.FrameArrived([&](Direct3D11CaptureFramePool const& sender, winrt::Windows::Foundation::IInspectable const&)
            {
                auto frame = sender.TryGetNextFrame();
                if (frame)
                {
                    didReceiveFrame = true;
                    SetEvent(frameEvent);
                }
            });

            session.StartCapture();
            DWORD waitResult = WaitForSingleObject(frameEvent, 3000);
            framePool.FrameArrived(token);
            session.Close();
            framePool.Close();
            CloseHandle(frameEvent);

            if (waitResult != WAIT_OBJECT_0 || !didReceiveFrame)
            {
                return PingCaptureCaptureFailure;
            }

            result.SourceSize = { size.Width, size.Height };
            result.Device = d3dDevice;
            return PingCaptureSuccess;
        }
        catch (hresult_error const& error)
        {
            if (error.code() == E_ACCESSDENIED || error.code() == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED))
            {
                return PingCaptureAccessDenied;
            }

            return PingCaptureCaptureFailure;
        }
        catch (...)
        {
            return PingCaptureCaptureFailure;
        }
    }
}
