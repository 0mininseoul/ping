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
    int Record(string path, int durationMs, int monitor, double faceRatio, ScreenCaptureViewport viewport,
        string cameraDeviceId, string microphoneEndpointId, SafeWaitHandle cancellationEvent,
        Action<CapturePreviewFrame> preview, out double aspect)
        => throw new NotSupportedException("Native API does not support recording preview.");
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

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate void PreviewCallback(nint pixels, int width, int height, int stride, nint context);

    public int Record(string path, int durationMs, int monitor, double faceRatio, ScreenCaptureViewport viewport,
        string cameraDeviceId, string microphoneEndpointId, SafeWaitHandle cancellationEvent,
        Action<CapturePreviewFrame> preview, out double aspect)
    {
        PreviewCallback callback = (pixels, width, height, stride, _) =>
        {
            try
            {
                if (pixels == 0 || width < 2 || height < 2 || width > 1920 || height > 1920 || stride != width * 4) return;
                var copy = new byte[checked(stride * height)];
                Marshal.Copy(pixels, copy, 0, copy.Length);
                preview(new(width, height, copy));
            }
            catch (Exception) { System.Diagnostics.Debug.WriteLine("Ping recording preview frame was skipped."); }
        };
        try
        {
            return PingCapture_RecordScreenFaceMp4V5(path, durationMs, monitor, faceRatio, viewport.Zoom,
                viewport.CenterX, viewport.CenterY, cameraDeviceId, microphoneEndpointId, cancellationEvent, callback, 0, out aspect);
        }
        finally { GC.KeepAlive(callback); }
    }

    [DllImport(Library, CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_RecordScreenFaceMp4V5(string path, int durationMs, int monitor,
        double faceRatio, double zoom, double centerX, double centerY, string cameraDeviceId, string microphoneEndpointId,
        SafeWaitHandle cancellationEvent, PreviewCallback preview, nint context, out double aspect);

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
