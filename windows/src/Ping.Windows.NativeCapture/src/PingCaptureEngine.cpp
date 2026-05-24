#include "PingCaptureEngine.h"

#include <cmath>
#include <future>

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
int __stdcall PingScreenCaptureSelfTest()
{
    return PingCapture_SelfTestScreenCapture();
}
