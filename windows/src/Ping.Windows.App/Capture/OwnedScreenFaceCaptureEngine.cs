using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

public sealed class OwnedScreenFaceCaptureEngine(CameraOwnership camera, IScreenFaceCaptureEngine engine, CameraLease? borrowed = null)
    : IScreenFaceCaptureEngine
{
    public async Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, CancellationToken token)
        => await RecordOwnedAsync(active => engine.RecordAsync(duration, monitorIndex, active), token);

    public async Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, ScreenCaptureViewport viewport,
        CancellationToken token) => await RecordOwnedAsync(active => engine.RecordAsync(duration, monitorIndex, viewport, active), token);

    private async Task<ScreenFaceCaptureResult> RecordOwnedAsync(Func<CancellationToken, Task<ScreenFaceCaptureResult>> record, CancellationToken token)
    {
        using var lease = borrowed is null ? await camera.AcquireManualAsync(token) : null;
        var active = borrowed ?? lease ?? throw new InvalidOperationException("카메라가 다른 촬영에서 사용 중입니다.");
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(token, active.Token);
        cancellation.Token.ThrowIfCancellationRequested();
        return await record(cancellation.Token);
    }

    public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, CancellationToken token) => engine.CapturePreviewAsync(monitorIndex, token);
    public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, ScreenCaptureViewport viewport,
        CancellationToken token) => engine.CapturePreviewAsync(monitorIndex, viewport, token);
    public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => engine.SelfTestAsync();
}
