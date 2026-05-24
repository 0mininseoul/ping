#include "PingCaptureEngine.h"

#include <cmath>

using namespace Ping::Windows::NativeCapture;

namespace
{
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

    MonitorCaptureResult monitorResult{};
    int screenResult = CaptureOneMonitorFrame(targetMonitorIndex, monitorResult);
    if (screenResult != PingCaptureSuccess)
    {
        return NormalizeCaptureFailure(screenResult);
    }

    int cameraResult = ProbeCameraFrameSource();
    if (cameraResult != PingCaptureSuccess)
    {
        return cameraResult;
    }

    OutputLayout layout = CreateScreenFaceLayout(monitorResult.SourceSize, faceDiameterRatio);
    if (outAspectRatio != nullptr)
    {
        *outAspectRatio = SafeAspectRatio(layout);
    }

    int writerResult = InitializeMp4SinkWriter(outputPath, layout, durationMs);
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
int __stdcall PingScreenCaptureSelfTest()
{
    return PingCapture_SelfTestScreenCapture();
}
