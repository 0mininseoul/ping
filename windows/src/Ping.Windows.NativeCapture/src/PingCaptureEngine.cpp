#include "PingCaptureEngine.h"
#include "LiveRecording.h"

#include <cmath>
#include <limits>

using namespace Ping::Windows::NativeCapture;

namespace
{
    int RecordScreenFace(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
        double faceDiameterRatio, double zoom, double centerX, double centerY, const wchar_t* cameraDeviceId,
        const wchar_t* microphoneEndpointId, HANDLE cancellationEvent, double* outAspectRatio,
        PingCapturePreviewCallback preview = nullptr, void* previewContext = nullptr);
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
    return PingCapture_RecordScreenFaceMp4V2(outputPath, durationMs, targetMonitorIndex, faceDiameterRatio,
        1, .5, .5, nullptr, outAspectRatio);
}

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4V2(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
    double faceDiameterRatio, double zoom, double centerX, double centerY, HANDLE cancellationEvent, double* outAspectRatio)
{
    return RecordScreenFace(outputPath, durationMs, targetMonitorIndex, faceDiameterRatio, zoom, centerX, centerY,
        nullptr, nullptr, cancellationEvent, outAspectRatio);
}

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4V3(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
    double faceDiameterRatio, double zoom, double centerX, double centerY, const wchar_t* cameraDeviceId,
    HANDLE cancellationEvent, double* outAspectRatio)
{
    if (!cameraDeviceId || !cameraDeviceId[0])
    {
        if (outAspectRatio) *outAspectRatio = 1;
        return PingCaptureNoCamera;
    }
    return RecordScreenFace(outputPath, durationMs, targetMonitorIndex, faceDiameterRatio, zoom, centerX, centerY,
        cameraDeviceId, nullptr, cancellationEvent, outAspectRatio);
}

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4V4(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
    double faceDiameterRatio, double zoom, double centerX, double centerY, const wchar_t* cameraDeviceId,
    const wchar_t* microphoneEndpointId, HANDLE cancellationEvent, double* outAspectRatio)
{
    if (outAspectRatio) *outAspectRatio = 1;
    if (!cameraDeviceId || !cameraDeviceId[0]) return PingCaptureNoCamera;
    if (!microphoneEndpointId || !microphoneEndpointId[0]) return PingCaptureNoMicrophone;
    return RecordScreenFace(outputPath, durationMs, targetMonitorIndex, faceDiameterRatio, zoom, centerX, centerY,
        cameraDeviceId, microphoneEndpointId, cancellationEvent, outAspectRatio);
}

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4V5(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
    double faceDiameterRatio, double zoom, double centerX, double centerY, const wchar_t* cameraDeviceId,
    const wchar_t* microphoneEndpointId, HANDLE cancellationEvent, PingCapturePreviewCallback preview,
    void* previewContext, double* outAspectRatio)
{
    if (outAspectRatio) *outAspectRatio = 1;
    if (!cameraDeviceId || !cameraDeviceId[0]) return PingCaptureNoCamera;
    if (!microphoneEndpointId || !microphoneEndpointId[0]) return PingCaptureNoMicrophone;
    return RecordScreenFace(outputPath, durationMs, targetMonitorIndex, faceDiameterRatio, zoom, centerX, centerY,
        cameraDeviceId, microphoneEndpointId, cancellationEvent, outAspectRatio, preview, previewContext);
}

namespace
{
int RecordScreenFace(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
    double faceDiameterRatio, double zoom, double centerX, double centerY, const wchar_t* cameraDeviceId,
    const wchar_t* microphoneEndpointId, HANDLE cancellationEvent, double* outAspectRatio,
    PingCapturePreviewCallback preview, void* previewContext)
try
{
    if (outAspectRatio != nullptr)
    {
        *outAspectRatio = 1.0;
    }

    if (outputPath == nullptr || outputPath[0] == L'\0' || !IsValidDuration(durationMs))
    {
        return PingCaptureEncoderFailure;
    }

    if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;

    OutputLayout layout{};
    std::unique_ptr<IRecordingFrameProvider> provider;
    auto sourceResult = CreateLiveRecordingProvider(targetMonitorIndex, faceDiameterRatio, {zoom, centerX, centerY}, durationMs,
        layout, provider, cameraDeviceId ? cameraDeviceId : L"", microphoneEndpointId ? microphoneEndpointId : L"");
    if (sourceResult != PingCaptureSuccess || !provider) return NormalizeCaptureFailure(sourceResult);
    if (outAspectRatio != nullptr)
    {
        *outAspectRatio = SafeAspectRatio(layout);
    }

    // Producers already apply the frozen viewport before publishing bounded CPU frames.
    int writerResult = WriteScreenFaceMp4Stream(outputPath, layout, *provider, durationMs, {}, cancellationEvent, preview, previewContext);
    if (writerResult != PingCaptureSuccess)
    {
        DeleteFileW(outputPath);
        return writerResult;
    }

    return PingCaptureSuccess;
}
catch (...)
{
    if (outputPath) DeleteFileW(outputPath);
    return PingCaptureCaptureFailure;
}
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
    return PingCapture_WriteScreenPreviewBmpV2(outputPath, targetMonitorIndex, 1, .5, .5, nullptr, outAspectRatio);
}

extern "C" __declspec(dllexport)
int PingCapture_WriteScreenPreviewBmpV2(const wchar_t* outputPath, int targetMonitorIndex,
    double zoom, double centerX, double centerY, HANDLE cancellationEvent, double* outAspectRatio)
try
{
    if (outAspectRatio != nullptr)
    {
        *outAspectRatio = 1.0;
    }

    if (outputPath == nullptr || outputPath[0] == L'\0')
    {
        return PingCaptureCaptureFailure;
    }

    if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;

    MonitorCaptureResult monitorResult{};
    int captureResult = CaptureMonitorPreviewFrame(targetMonitorIndex, {zoom, centerX, centerY}, cancellationEvent, monitorResult);
    if (captureResult != PingCaptureSuccess)
    {
        return NormalizeCaptureFailure(captureResult);
    }

    if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;

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
catch (...)
{
    if (outputPath) DeleteFileW(outputPath);
    return PingCaptureCaptureFailure;
}

extern "C" __declspec(dllexport)
int __stdcall PingScreenCaptureSelfTest()
{
    return PingCapture_SelfTestScreenCapture();
}
