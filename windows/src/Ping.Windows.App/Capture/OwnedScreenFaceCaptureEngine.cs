using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

public sealed class OwnedScreenFaceCaptureEngine(CameraOwnership camera, IScreenFaceCaptureEngine engine, CameraLease? borrowed = null,
    Func<CancellationToken, Task<string>>? selectCamera = null,
    Func<CancellationToken, Task<CaptureMicrophoneDevice>>? selectMicrophone = null)
    : IScreenFaceCaptureEngine, IRecordingPreviewCaptureEngine
{
    public async Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, CancellationToken token)
        => await RecordOwnedAsync(duration, monitorIndex, new(), active => engine.RecordAsync(duration, monitorIndex, active), token);

    public async Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, ScreenCaptureViewport viewport,
        CancellationToken token) => await RecordOwnedAsync(duration, monitorIndex, viewport, active => engine.RecordAsync(duration, monitorIndex, viewport, active), token);

    private async Task<ScreenFaceCaptureResult> RecordOwnedAsync(TimeSpan duration, int monitor, ScreenCaptureViewport viewport,
        Func<CancellationToken, Task<ScreenFaceCaptureResult>> record, CancellationToken token, Action<CapturePreviewFrame>? preview = null)
    {
        using var lease = borrowed is null ? await camera.AcquireManualAsync(token) : null;
        var active = borrowed ?? lease ?? throw new InvalidOperationException("카메라가 다른 촬영에서 사용 중입니다.");
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(token, active.Token);
        cancellation.Token.ThrowIfCancellationRequested();
        if (engine is IDeviceBoundScreenCaptureEngine devices)
        {
            var deviceId = await active.CameraSelection.GetAsync(selectCamera ?? SelectDefaultCameraAsync, cancellation.Token);
            var microphone = await active.MicrophoneSelection.GetAsync(selectMicrophone ?? SelectDefaultMicrophoneAsync, cancellation.Token);
            if (preview is not null && engine is IDeviceBoundRecordingPreviewEngine live)
                return await live.RecordAsync(duration, monitor, viewport, deviceId, microphone, preview, cancellation.Token);
            if (preview is not null) throw new NotSupportedException("Capture engine does not support recording preview.");
            return await devices.RecordAsync(duration, monitor, viewport, deviceId, microphone, cancellation.Token);
        }
        if (engine is ICameraBoundScreenCaptureEngine selected)
        {
            var deviceId = await active.CameraSelection.GetAsync(selectCamera ?? SelectDefaultCameraAsync, cancellation.Token);
            return await selected.RecordAsync(duration, monitor, viewport, deviceId, cancellation.Token);
        }
        return await record(cancellation.Token);
    }

    public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, ScreenCaptureViewport viewport,
        Action<CapturePreviewFrame> preview, CancellationToken token)
        => RecordOwnedAsync(duration, monitor, viewport,
            active => engine is IRecordingPreviewCaptureEngine live ? live.RecordAsync(duration, monitor, viewport, preview, active)
                : throw new NotSupportedException("Capture engine does not support recording preview."), token, preview);

    public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, CancellationToken token) => engine.CapturePreviewAsync(monitorIndex, token);
    public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, ScreenCaptureViewport viewport,
        CancellationToken token) => engine.CapturePreviewAsync(monitorIndex, viewport, token);
    public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => engine.SelfTestAsync();

    private static Task<string> SelectDefaultCameraAsync(CancellationToken token)
    {
#if WINDOWS
        return CaptureCameraResolver.ResolveAsync(token);
#else
        throw new PlatformNotSupportedException("A camera resolver is required outside Windows.");
#endif
    }

    private static Task<CaptureMicrophoneDevice> SelectDefaultMicrophoneAsync(CancellationToken token)
    {
#if WINDOWS
        return CaptureMicrophoneResolver.ResolveAsync(token);
#else
        throw new PlatformNotSupportedException("A microphone resolver is required outside Windows.");
#endif
    }
}
