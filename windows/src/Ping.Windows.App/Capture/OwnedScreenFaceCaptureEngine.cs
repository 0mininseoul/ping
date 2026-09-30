using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

public sealed class OwnedScreenFaceCaptureEngine(CameraOwnership camera, IScreenFaceCaptureEngine engine, CameraLease? borrowed = null)
    : IScreenFaceCaptureEngine
{
    public async Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, CancellationToken token)
    {
        using var lease = borrowed is null ? await camera.AcquireManualAsync(token) : null;
        var active = borrowed ?? lease ?? throw new InvalidOperationException("카메라가 다른 촬영에서 사용 중입니다.");
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(token, active.Token);
        cancellation.Token.ThrowIfCancellationRequested();
        return await engine.RecordAsync(duration, monitorIndex, cancellation.Token);
    }

    public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, CancellationToken token) => engine.CapturePreviewAsync(monitorIndex, token);
    public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => engine.SelfTestAsync();
}
