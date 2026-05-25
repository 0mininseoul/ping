#include "PingCaptureEngine.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <utility>
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

    bool IsAllBlack(std::vector<std::uint8_t> const& pixels)
    {
        for (size_t index = 0; index + 3 < pixels.size(); index += 4)
        {
            if (pixels[index] > 2 || pixels[index + 1] > 2 || pixels[index + 2] > 2)
            {
                return false;
            }
        }

        return true;
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
        using namespace winrt::Windows::Graphics::Capture;
        using namespace winrt::Windows::Graphics::DirectX;
        using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

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
            ComPtr<ID3D11DeviceContext> d3dContext;
            d3dDevice->GetImmediateContext(&d3dContext);

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
            ComPtr<ID3D11Texture2D> capturedTexture;
            auto token = framePool.FrameArrived([&](Direct3D11CaptureFramePool const& sender, winrt::Windows::Foundation::IInspectable const&)
            {
                auto frame = sender.TryGetNextFrame();
                if (frame)
                {
                    auto surface = frame.Surface();
                    auto access = surface.as<IDirect3DDxgiInterfaceAccess>();
                    HRESULT textureResult = access->GetInterface(
                        __uuidof(ID3D11Texture2D),
                        reinterpret_cast<void**>(capturedTexture.ReleaseAndGetAddressOf()));
                    if (SUCCEEDED(textureResult))
                    {
                        didReceiveFrame = true;
                        SetEvent(frameEvent);
                    }
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

            if (!capturedTexture)
            {
                return PingCaptureProtectedContent;
            }

            D3D11_TEXTURE2D_DESC capturedDesc{};
            capturedTexture->GetDesc(&capturedDesc);
            D3D11_TEXTURE2D_DESC stagingDesc = capturedDesc;
            stagingDesc.BindFlags = 0;
            stagingDesc.MiscFlags = 0;
            stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
            stagingDesc.Usage = D3D11_USAGE_STAGING;

            ComPtr<ID3D11Texture2D> stagingTexture;
            check_hresult(d3dDevice->CreateTexture2D(&stagingDesc, nullptr, &stagingTexture));
            d3dContext->CopyResource(stagingTexture.Get(), capturedTexture.Get());

            D3D11_MAPPED_SUBRESOURCE mapped{};
            check_hresult(d3dContext->Map(stagingTexture.Get(), 0, D3D11_MAP_READ, 0, &mapped));

            result.BgraPixels.resize(static_cast<size_t>(size.Height) * static_cast<size_t>(size.Width) * 4);
            for (int y = 0; y < size.Height; ++y)
            {
                auto* source = static_cast<std::uint8_t*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch;
                auto* destination = result.BgraPixels.data() + static_cast<size_t>(y) * static_cast<size_t>(size.Width) * 4;
                std::memcpy(destination, source, static_cast<size_t>(size.Width) * 4);
            }
            d3dContext->Unmap(stagingTexture.Get(), 0);

            if (IsAllBlack(result.BgraPixels))
            {
                return PingCaptureProtectedContent;
            }

            result.SourceSize = { size.Width, size.Height };
            result.RowPitch = static_cast<std::uint32_t>(size.Width * 4);
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

    int CaptureMonitorFrames(
        int targetMonitorIndex,
        int durationMs,
        int framesPerSecond,
        std::vector<MonitorCaptureResult>& result)
    {
        result.clear();
        if (durationMs <= 0 || framesPerSecond <= 0)
        {
            return PingCaptureCaptureFailure;
        }

        int apartmentResult = EnsureApartment();
        if (apartmentResult != PingCaptureSuccess)
        {
            return apartmentResult;
        }

        using namespace winrt;
        using namespace winrt::Windows::Graphics::Capture;
        using namespace winrt::Windows::Graphics::DirectX;
        using namespace winrt::Windows::Graphics::DirectX::Direct3D11;

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
            ComPtr<ID3D11DeviceContext> d3dContext;
            d3dDevice->GetImmediateContext(&d3dContext);

            ComPtr<IDXGIDevice> dxgiDevice;
            check_hresult(d3dDevice.As(&dxgiDevice));

            com_ptr<::IInspectable> inspectableDevice;
            check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.Get(), inspectableDevice.put()));
            auto direct3DDevice = inspectableDevice.as<IDirect3DDevice>();

            auto framePool = Direct3D11CaptureFramePool::CreateFreeThreaded(
                direct3DDevice,
                DirectXPixelFormat::B8G8R8A8UIntNormalized,
                2,
                size);
            auto session = framePool.CreateCaptureSession(item);

            HANDLE doneEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
            if (doneEvent == nullptr)
            {
                return PingCaptureCaptureFailure;
            }

            int frameCount = std::max(1, (durationMs * framesPerSecond + 999) / 1000);
            result.reserve(static_cast<size_t>(frameCount));
            std::mutex framesLock;
            std::atomic_bool protectedFrame = false;
            auto startedAt = std::chrono::steady_clock::now();

            auto token = framePool.FrameArrived([&](Direct3D11CaptureFramePool const& sender, winrt::Windows::Foundation::IInspectable const&)
            {
                auto now = std::chrono::steady_clock::now();
                auto elapsedMs = static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(now - startedAt).count());
                auto scheduledIndex = std::min(
                    frameCount - 1,
                    std::max(0, (elapsedMs * framesPerSecond) / 1000));

                auto frame = sender.TryGetNextFrame();
                if (!frame)
                {
                    if (elapsedMs >= durationMs)
                    {
                        SetEvent(doneEvent);
                    }
                    return;
                }

                auto surface = frame.Surface();
                auto access = surface.as<IDirect3DDxgiInterfaceAccess>();
                ComPtr<ID3D11Texture2D> capturedTexture;
                HRESULT textureResult = access->GetInterface(
                    __uuidof(ID3D11Texture2D),
                    reinterpret_cast<void**>(capturedTexture.GetAddressOf()));
                if (FAILED(textureResult) || !capturedTexture)
                {
                    return;
                }

                D3D11_TEXTURE2D_DESC capturedDesc{};
                capturedTexture->GetDesc(&capturedDesc);
                D3D11_TEXTURE2D_DESC stagingDesc = capturedDesc;
                stagingDesc.BindFlags = 0;
                stagingDesc.MiscFlags = 0;
                stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
                stagingDesc.Usage = D3D11_USAGE_STAGING;

                ComPtr<ID3D11Texture2D> stagingTexture;
                if (FAILED(d3dDevice->CreateTexture2D(&stagingDesc, nullptr, &stagingTexture)))
                {
                    return;
                }
                d3dContext->CopyResource(stagingTexture.Get(), capturedTexture.Get());

                D3D11_MAPPED_SUBRESOURCE mapped{};
                if (FAILED(d3dContext->Map(stagingTexture.Get(), 0, D3D11_MAP_READ, 0, &mapped)))
                {
                    return;
                }

                MonitorCaptureResult captured{};
                captured.SourceSize = { size.Width, size.Height };
                captured.RowPitch = static_cast<std::uint32_t>(size.Width * 4);
                captured.Device = d3dDevice;
                captured.BgraPixels.resize(static_cast<size_t>(size.Height) * static_cast<size_t>(size.Width) * 4);
                for (int y = 0; y < size.Height; ++y)
                {
                    auto* source = static_cast<std::uint8_t*>(mapped.pData) + static_cast<size_t>(y) * mapped.RowPitch;
                    auto* destination = captured.BgraPixels.data() + static_cast<size_t>(y) * static_cast<size_t>(size.Width) * 4;
                    std::memcpy(destination, source, static_cast<size_t>(size.Width) * 4);
                }
                d3dContext->Unmap(stagingTexture.Get(), 0);

                if (IsAllBlack(captured.BgraPixels))
                {
                    protectedFrame = true;
                    SetEvent(doneEvent);
                    return;
                }

                std::lock_guard lock(framesLock);
                if (static_cast<int>(result.size()) <= scheduledIndex)
                {
                    result.push_back(std::move(captured));
                }

                if (elapsedMs >= durationMs)
                {
                    SetEvent(doneEvent);
                }
            });

            session.StartCapture();
            DWORD waitResult = WaitForSingleObject(doneEvent, static_cast<DWORD>(durationMs + 1000));
            framePool.FrameArrived(token);
            session.Close();
            framePool.Close();
            CloseHandle(doneEvent);

            if (protectedFrame)
            {
                return PingCaptureProtectedContent;
            }

            if (result.empty())
            {
                return waitResult == WAIT_OBJECT_0 ? PingCaptureCaptureFailure : PingCaptureCaptureFailure;
            }

            while (static_cast<int>(result.size()) < frameCount)
            {
                result.push_back(result.back());
            }

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
