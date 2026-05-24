#include "PingCaptureEngine.h"

#include <cmath>
#include <future>
#include <limits>

using namespace Ping::Windows::NativeCapture;

namespace
{
    constexpr int CaptureFramesPerSecond = 15;

    bool IsValidDuration(int durationMs)
    {
        return durationMs > 0 && durationMs <= 30'000;
    }

    double SafeAspectRatio(OutputLayout const& layout)
    {
        if (layout.AspectRatio > 0 && std::isfinite(layout.AspectRatio))
        {
            return layout.AspectRatio;
        }

        return 16.0 / 9.0;
    }

    int NormalizeCaptureFailure(int errorCode)
    {
        return errorCode == PingCaptureSuccess ? PingCaptureCaptureFailure : errorCode;
    }

    bool WriteAll(HANDLE file, void const* data, DWORD byteCount)
    {
        DWORD written = 0;
        return WriteFile(file, data, byteCount, &written, nullptr) && written == byteCount;
    }
}

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4(
    const wchar_t* outputPath,
    int durationMs,
    int targetMonitorIndex,
    double faceDiameterRatio,
    double* outAspectRatio)
{
    if (outAspectRatio != nullptr)
    {
        *outAspectRatio = 1.0;
    }

    if (outputPath == nullptr || outputPath[0] == L'\0' || !IsValidDuration(durationMs))
    {
        return PingCaptureEncoderFailure;
    }

    std::vector<MonitorCaptureResult> monitorFrames;
    std::vector<CameraFrameResult> cameraFrames;
    AudioCaptureResult audio{};

    auto screenCapture = std::async(std::launch::async, [&]
    {
        return CaptureMonitorFrames(targetMonitorIndex, durationMs, CaptureFramesPerSecond, monitorFrames);
    });
    auto cameraCapture = std::async(std::launch::async, [&]
    {
        return CaptureCameraFrames(durationMs, CaptureFramesPerSecond, cameraFrames);
    });
    auto audioCapture = std::async(std::launch::async, [&]
    {
        return CaptureMicrophonePcm(durationMs, audio);
    });

    int screenResult = PingCaptureCaptureFailure;
    int cameraResult = PingCaptureNoCamera;
    int audioResult = PingCaptureNoMicrophone;
    try
    {
        screenResult = screenCapture.get();
        cameraResult = cameraCapture.get();
        audioResult = audioCapture.get();
    }
    catch (...)
    {
        return PingCaptureCaptureFailure;
    }

    if (screenResult != PingCaptureSuccess)
    {
        return NormalizeCaptureFailure(screenResult);
    }

    if (cameraResult != PingCaptureSuccess)
    {
        return cameraResult;
    }

    if (audioResult != PingCaptureSuccess)
    {
        return audioResult;
    }

    OutputLayout layout = CreateScreenFaceLayout(monitorFrames.front().SourceSize, faceDiameterRatio);
    if (outAspectRatio != nullptr)
    {
        *outAspectRatio = SafeAspectRatio(layout);
    }

    int writerResult = WriteScreenFaceMp4(outputPath, layout, monitorFrames, cameraFrames, audio, durationMs);
    if (writerResult != PingCaptureSuccess)
    {
        DeleteFileW(outputPath);
        return writerResult;
    }

    return PingCaptureSuccess;
}

extern "C" __declspec(dllexport)
int PingCapture_SelfTestScreenCapture()
{
    MonitorCaptureResult monitorResult{};
    return CaptureOneMonitorFrame(-1, monitorResult);
}

extern "C" __declspec(dllexport)
int PingCapture_WriteScreenPreviewBmp(
    const wchar_t* outputPath,
    int targetMonitorIndex,
    double* outAspectRatio)
{
    if (outAspectRatio != nullptr)
    {
        *outAspectRatio = 1.0;
    }

    if (outputPath == nullptr || outputPath[0] == L'\0')
    {
        return PingCaptureCaptureFailure;
    }

    MonitorCaptureResult monitorResult{};
    int captureResult = CaptureOneMonitorFrame(targetMonitorIndex, monitorResult);
    if (captureResult != PingCaptureSuccess)
    {
        return NormalizeCaptureFailure(captureResult);
    }

    if (monitorResult.SourceSize.Width <= 0
        || monitorResult.SourceSize.Height <= 0
        || monitorResult.BgraPixels.empty()
        || monitorResult.BgraPixels.size() > std::numeric_limits<DWORD>::max())
    {
        return PingCaptureCaptureFailure;
    }

    if (outAspectRatio != nullptr)
    {
        *outAspectRatio =
            static_cast<double>(monitorResult.SourceSize.Width)
            / static_cast<double>(monitorResult.SourceSize.Height);
    }

    BITMAPFILEHEADER fileHeader{};
    BITMAPINFOHEADER infoHeader{};
    auto const pixelByteCount = static_cast<DWORD>(monitorResult.BgraPixels.size());
    fileHeader.bfType = 0x4D42;
    fileHeader.bfOffBits = static_cast<DWORD>(sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER));
    if (pixelByteCount > std::numeric_limits<DWORD>::max() - fileHeader.bfOffBits)
    {
        return PingCaptureCaptureFailure;
    }

    fileHeader.bfSize = fileHeader.bfOffBits + pixelByteCount;

    infoHeader.biSize = sizeof(BITMAPINFOHEADER);
    infoHeader.biWidth = monitorResult.SourceSize.Width;
    infoHeader.biHeight = -monitorResult.SourceSize.Height;
    infoHeader.biPlanes = 1;
    infoHeader.biBitCount = 32;
    infoHeader.biCompression = BI_RGB;
    infoHeader.biSizeImage = pixelByteCount;

    HANDLE file = CreateFileW(
        outputPath,
        GENERIC_WRITE,
        0,
        nullptr,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_TEMPORARY,
        nullptr);
    if (file == INVALID_HANDLE_VALUE)
    {
        return PingCaptureCaptureFailure;
    }

    bool ok = WriteAll(file, &fileHeader, static_cast<DWORD>(sizeof(fileHeader)))
        && WriteAll(file, &infoHeader, static_cast<DWORD>(sizeof(infoHeader)))
        && WriteAll(file, monitorResult.BgraPixels.data(), pixelByteCount);
    CloseHandle(file);

    if (!ok)
    {
        DeleteFileW(outputPath);
        return PingCaptureCaptureFailure;
    }

    return PingCaptureSuccess;
}

extern "C" __declspec(dllexport)
int __stdcall PingScreenCaptureSelfTest()
{
    return PingCapture_SelfTestScreenCapture();
}
