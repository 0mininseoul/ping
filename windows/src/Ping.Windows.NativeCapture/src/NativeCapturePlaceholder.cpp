#include <atomic>
#include <d3d11.h>
#include <dxgi.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <windows.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/base.h>

extern "C" __declspec(dllexport) int PingWindowsNativeCapturePlaceholder()
{
    return 0;
}

extern "C" __declspec(dllexport) int __stdcall PingScreenCaptureSelfTest()
{
    using namespace winrt;
    using namespace Windows::Graphics::Capture;
    using namespace Windows::Graphics::DirectX;
    using namespace Windows::Graphics::DirectX::Direct3D11;

    try
    {
        try
        {
            init_apartment(apartment_type::multi_threaded);
        }
        catch (hresult_error const& error)
        {
            if (error.code() != RPC_E_CHANGED_MODE)
            {
                throw;
            }
        }

        if (!GraphicsCaptureSession::IsSupported())
        {
            return 2;
        }

        POINT origin{};
        HMONITOR monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
        if (monitor == nullptr)
        {
            return 3;
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
            return 3;
        }

        D3D_FEATURE_LEVEL featureLevels[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
        com_ptr<ID3D11Device> d3dDevice;
        D3D_FEATURE_LEVEL featureLevel{};
        HRESULT hr = D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_HARDWARE,
            nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            featureLevels,
            ARRAYSIZE(featureLevels),
            D3D11_SDK_VERSION,
            d3dDevice.put(),
            &featureLevel,
            nullptr);

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
                d3dDevice.put(),
                &featureLevel,
                nullptr);
        }
        check_hresult(hr);

        com_ptr<IDXGIDevice> dxgiDevice;
        d3dDevice.as(dxgiDevice);

        com_ptr<::IInspectable> inspectableDevice;
        check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.get(), inspectableDevice.put()));
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
            return 3;
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

        return waitResult == WAIT_OBJECT_0 && didReceiveFrame ? 0 : 3;
    }
    catch (hresult_error const& error)
    {
        if (error.code() == E_ACCESSDENIED || error.code() == HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED))
        {
            return 1;
        }

        return 3;
    }
    catch (...)
    {
        return 3;
    }
}
