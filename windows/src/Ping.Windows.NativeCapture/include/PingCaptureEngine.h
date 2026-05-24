#pragma once

#include <windows.h>

enum PingCaptureErrorCode
{
    PingCaptureSuccess = 0,
    PingCaptureUnsupportedOs = 1,
    PingCaptureAccessDenied = 2,
    PingCaptureNoMonitor = 3,
    PingCaptureNoCamera = 4,
    PingCaptureEncoderFailure = 5,
    PingCaptureCaptureFailure = 6
};

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4(
    const wchar_t* outputPath,
    int durationMs,
    int targetMonitorIndex,
    double faceDiameterRatio,
    double* outAspectRatio);

extern "C" __declspec(dllexport)
int PingCapture_SelfTestScreenCapture();

extern "C" __declspec(dllexport)
int __stdcall PingScreenCaptureSelfTest();

#ifdef __cplusplus

#include <d3d11.h>
#include <wrl/client.h>

namespace Ping::Windows::NativeCapture
{
    struct CaptureSize
    {
        int Width;
        int Height;
    };

    struct OutputLayout
    {
        int Width;
        int Height;
        int FaceDiameter;
        int FaceX;
        int FaceY;
        double AspectRatio;
    };

    struct MonitorCaptureResult
    {
        CaptureSize SourceSize;
        Microsoft::WRL::ComPtr<ID3D11Device> Device;
    };

    int CaptureOneMonitorFrame(int targetMonitorIndex, MonitorCaptureResult& result);
    int ProbeCameraFrameSource();
    OutputLayout CreateScreenFaceLayout(CaptureSize sourceSize, double faceDiameterRatio);
    int InitializeMp4SinkWriter(const wchar_t* outputPath, OutputLayout const& layout, int durationMs);
}

#endif
