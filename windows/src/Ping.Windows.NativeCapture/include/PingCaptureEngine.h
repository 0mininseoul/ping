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
    PingCaptureCaptureFailure = 6,
    PingCaptureProtectedContent = 7,
    PingCaptureNoMicrophone = 8,
    PingCaptureCancelled = 9
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
int PingCapture_WriteScreenPreviewBmp(
    const wchar_t* outputPath,
    int targetMonitorIndex,
    double* outAspectRatio);

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4V2(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
    double faceDiameterRatio, double zoom, double centerX, double centerY, HANDLE cancellationEvent, double* outAspectRatio);

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4V3(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
    double faceDiameterRatio, double zoom, double centerX, double centerY, const wchar_t* cameraDeviceId,
    HANDLE cancellationEvent, double* outAspectRatio);

extern "C" __declspec(dllexport)
int PingCapture_GetDefaultMicrophoneIdentity(wchar_t* endpointId, int endpointCapacity, wchar_t* instanceId, int instanceCapacity);

extern "C" __declspec(dllexport)
int PingCapture_RecordScreenFaceMp4V4(const wchar_t* outputPath, int durationMs, int targetMonitorIndex,
    double faceDiameterRatio, double zoom, double centerX, double centerY, const wchar_t* cameraDeviceId,
    const wchar_t* microphoneEndpointId, HANDLE cancellationEvent, double* outAspectRatio);

extern "C" __declspec(dllexport)
int PingCapture_WriteScreenPreviewBmpV2(const wchar_t* outputPath, int targetMonitorIndex,
    double zoom, double centerX, double centerY, HANDLE cancellationEvent, double* outAspectRatio);

// Compatibility alias used by the Task 3 onboarding probe.
// Returns the same PingCaptureErrorCode values as PingCapture_SelfTestScreenCapture.
extern "C" __declspec(dllexport)
int __stdcall PingScreenCaptureSelfTest();

#ifdef __cplusplus

#include <d3d11.h>
#include <cstdint>
#include <vector>
#include <wrl/client.h>

namespace Ping::Windows::NativeCapture
{
    struct CaptureSize
    {
        int Width;
        int Height;
    };

    struct CaptureViewport
    {
        double Zoom = 1;
        double CenterX = 0.5;
        double CenterY = 0.5;
    };

    struct CaptureCrop
    {
        int X;
        int Y;
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
        std::uint32_t RowPitch;
        std::vector<std::uint8_t> BgraPixels;
        Microsoft::WRL::ComPtr<ID3D11Device> Device;
    };

    struct CameraFrameResult
    {
        CaptureSize SourceSize;
        std::uint32_t RowPitch;
        std::vector<std::uint8_t> BgraPixels;
    };

    struct AudioCaptureResult
    {
        std::uint32_t SamplesPerSecond;
        std::uint32_t Channels;
        std::uint32_t BitsPerSample;
        std::vector<std::uint8_t> PcmBytes;
    };

    int CaptureOneMonitorFrame(int targetMonitorIndex, MonitorCaptureResult& result);
    int CaptureMonitorPreviewFrame(int targetMonitorIndex, CaptureViewport viewport, HANDLE cancellationEvent,
        MonitorCaptureResult& result);
    OutputLayout CreateScreenFaceLayout(CaptureSize sourceSize, double faceDiameterRatio, int maximumLongSide = 1920);
    CaptureCrop ComputeCaptureCrop(CaptureSize sourceSize, CaptureViewport viewport);
    int CropScreenFrame(MonitorCaptureResult const& source, CaptureViewport viewport,
        CaptureSize outputSize, MonitorCaptureResult& output);
    int ComposeScreenFaceFrame(OutputLayout const& layout, MonitorCaptureResult const& screen,
        CameraFrameResult const& camera, CaptureViewport viewport, std::vector<std::uint8_t>& output);
    int WriteScreenFaceMp4(
        const wchar_t* outputPath,
        OutputLayout const& layout,
        std::vector<MonitorCaptureResult> const& screenFrames,
        std::vector<CameraFrameResult> const& cameraFrames,
        AudioCaptureResult const& audio,
        int durationMs, CaptureViewport viewport = {}, HANDLE cancellationEvent = nullptr);
}

#endif
