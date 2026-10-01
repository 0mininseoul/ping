using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

public interface INativeScreenCaptureApi
{
    int Record(string path, int durationMs, int monitor, double faceRatio, ScreenCaptureViewport viewport,
        SafeWaitHandle cancellationEvent, out double aspect);
    int Record(string path, int durationMs, int monitor, double faceRatio, ScreenCaptureViewport viewport,
        string cameraDeviceId, SafeWaitHandle cancellationEvent, out double aspect)
        => throw new NotSupportedException("Native API does not support selected-camera recording.");
    int Preview(string path, int monitor, ScreenCaptureViewport viewport, SafeWaitHandle cancellationEvent, out double aspect);
    int Record(string path, int durationMs, int monitor, double faceRatio, ScreenCaptureViewport viewport,
        string cameraDeviceId, string microphoneEndpointId, SafeWaitHandle cancellationEvent, out double aspect)
        => throw new NotSupportedException("Native API does not support selected-device recording.");
    int SelfTest();
}

internal sealed class NativeScreenCaptureApi : INativeScreenCaptureApi
{
    private const string Library = "Ping.Windows.NativeCapture.dll";
    public int Record(string path, int durationMs, int monitor, double faceRatio, ScreenCaptureViewport viewport,
        SafeWaitHandle cancellationEvent, out double aspect) => PingCapture_RecordScreenFaceMp4V2(path, durationMs,
            monitor, faceRatio, viewport.Zoom, viewport.CenterX, viewport.CenterY, cancellationEvent, out aspect);
    public int Record(string path, int durationMs, int monitor, double faceRatio, ScreenCaptureViewport viewport,
        string cameraDeviceId, SafeWaitHandle cancellationEvent, out double aspect)
        => PingCapture_RecordScreenFaceMp4V3(path, durationMs, monitor, faceRatio, viewport.Zoom, viewport.CenterX,
            viewport.CenterY, cameraDeviceId, cancellationEvent, out aspect);
    public int Preview(string path, int monitor, ScreenCaptureViewport viewport, SafeWaitHandle cancellationEvent,
        out double aspect) => PingCapture_WriteScreenPreviewBmpV2(path, monitor, viewport.Zoom, viewport.CenterX,
            viewport.CenterY, cancellationEvent, out aspect);
    public int Record(string path, int durationMs, int monitor, double faceRatio, ScreenCaptureViewport viewport,
        string cameraDeviceId, string microphoneEndpointId, SafeWaitHandle cancellationEvent, out double aspect)
        => PingCapture_RecordScreenFaceMp4V4(path, durationMs, monitor, faceRatio, viewport.Zoom, viewport.CenterX,
            viewport.CenterY, cameraDeviceId, microphoneEndpointId, cancellationEvent, out aspect);
    public int SelfTest() => PingCapture_SelfTestScreenCapture();

    [DllImport(Library, CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_RecordScreenFaceMp4V2(string path, int durationMs, int monitor,
        double faceRatio, double zoom, double centerX, double centerY, SafeWaitHandle cancellationEvent, out double aspect);
    [DllImport(Library, CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_RecordScreenFaceMp4V3(string path, int durationMs, int monitor,
        double faceRatio, double zoom, double centerX, double centerY, string cameraDeviceId, SafeWaitHandle cancellationEvent, out double aspect);
    [DllImport(Library, CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_RecordScreenFaceMp4V4(string path, int durationMs, int monitor,
        double faceRatio, double zoom, double centerX, double centerY, string cameraDeviceId, string microphoneEndpointId,
        SafeWaitHandle cancellationEvent, out double aspect);
    [DllImport(Library, CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_WriteScreenPreviewBmpV2(string path, int monitor, double zoom,
        double centerX, double centerY, SafeWaitHandle cancellationEvent, out double aspect);
    [DllImport(Library, CallingConvention = CallingConvention.Winapi, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_SelfTestScreenCapture();
}
