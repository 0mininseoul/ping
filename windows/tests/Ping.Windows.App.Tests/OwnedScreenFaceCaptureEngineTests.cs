using Ping.Windows.App.Capture;
using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class OwnedScreenFaceCaptureEngineTests
{
    [Fact]
    public async Task QuickRecordingOwnsCameraUntilNativeWorkReturns()
    {
        var camera = new CameraOwnership();
        var native = new Engine();
        var recording = new OwnedScreenFaceCaptureEngine(camera, native).RecordAsync(TimeSpan.FromSeconds(3), 0, default);
        Assert.True(camera.IsBusy);
        Assert.Null(camera.TryAcquire(CameraPurpose.AutomaticReply));
        native.Complete();
        await recording;
        Assert.False(camera.IsBusy);
    }

    [Fact]
    public async Task ManualMirrorBorrowedLeaseIsNotReleasedByNativeRecord()
    {
        var camera = new CameraOwnership();
        using var lease = camera.TryAcquire(CameraPurpose.Manual)!;
        var native = new Engine();
        var recording = new OwnedScreenFaceCaptureEngine(camera, native, lease).RecordAsync(TimeSpan.FromSeconds(3), 0, default);
        native.Complete();
        await recording;
        Assert.True(camera.IsBusy);
        lease.Dispose();
        Assert.False(camera.IsBusy);
    }

    [Fact]
    public async Task AnotherManualMirrorCannotStartASecondCamera()
    {
        var camera = new CameraOwnership();
        using var mirror = camera.TryAcquire(CameraPurpose.Manual)!;
        var native = new Engine();
        await Assert.ThrowsAsync<InvalidOperationException>(() => new OwnedScreenFaceCaptureEngine(camera, native).RecordAsync(TimeSpan.FromSeconds(3), 0, default));
        Assert.Equal(0, native.Starts);
    }

    [Fact]
    public async Task NativeFailureStillReleasesOwnedCamera()
    {
        var camera = new CameraOwnership();
        var native = new Engine();
        var recording = new OwnedScreenFaceCaptureEngine(camera, native).RecordAsync(TimeSpan.FromSeconds(3), 0, default);
        native.Fail();
        await Assert.ThrowsAsync<IOException>(() => recording);
        Assert.False(camera.IsBusy);
    }

    private sealed class Engine : IScreenFaceCaptureEngine
    {
        private readonly TaskCompletionSource<ScreenFaceCaptureResult> result = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int Starts;
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, CancellationToken token) { ++Starts; return result.Task; }
        public void Complete() => result.SetResult(new("fixture.mp4", 16d / 9));
        public void Fail() => result.SetException(new IOException("device failed"));
        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitor, CancellationToken token) => throw new NotSupportedException();
        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => throw new NotSupportedException();
    }

    [Fact]
    public async Task NativeRecordingUsesTheCameraAlreadySelectedForPreview()
    {
        var camera = new CameraOwnership();
        using var lease = camera.TryAcquire(CameraPurpose.Manual)!;
        await lease.CameraSelection.GetAsync(_ => Task.FromResult("preview-camera"));
        var native = new SelectedEngine();
        var viewport = new ScreenCaptureViewport(2, .4, .6);
        await new OwnedScreenFaceCaptureEngine(camera, native, lease, _ => throw new Exception("must reuse preview choice"))
            .RecordAsync(TimeSpan.FromSeconds(3), 2, viewport, default);
        Assert.Equal("preview-camera", native.Device);
        Assert.Same(viewport, native.Viewport);
        Assert.True(camera.IsBusy);
    }

    [Fact]
    public async Task CancelDuringDeviceSelectionKeepsLeaseUntilEnumerationReturns()
    {
        var camera = new CameraOwnership();
        var native = new SelectedEngine();
        var ready = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var cancellation = new CancellationTokenSource();
        var recording = new OwnedScreenFaceCaptureEngine(camera, native, selectCamera: _ => ready.Task)
            .RecordAsync(TimeSpan.FromSeconds(3), 0, cancellation.Token);
        cancellation.Cancel();
        Assert.False(recording.IsCompleted);
        Assert.True(camera.IsBusy);
        ready.SetResult("camera");
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => recording);
        Assert.Null(native.Device);
        Assert.False(camera.IsBusy);
    }

    [Fact]
    public async Task MissingSelectedCameraDoesNotStartNativeDefaultCamera()
    {
        var camera = new CameraOwnership();
        var native = new SelectedEngine();
        await Assert.ThrowsAsync<InvalidOperationException>(() => new OwnedScreenFaceCaptureEngine(camera, native,
            selectCamera: _ => Task.FromResult(" ")).RecordAsync(TimeSpan.FromSeconds(3), 0, default));
        Assert.Null(native.Device);
        Assert.False(camera.IsBusy);
    }

    private sealed class SelectedEngine : IScreenFaceCaptureEngine, ICameraBoundScreenCaptureEngine
    {
        public string? Device;
        public ScreenCaptureViewport? Viewport;
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, ScreenCaptureViewport viewport,
            string cameraDeviceId, CancellationToken token)
        { Device = cameraDeviceId; Viewport = viewport; return Task.FromResult(new ScreenFaceCaptureResult("fixture.mp4", 1)); }
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, CancellationToken token) => throw new Exception("unselected recording");
        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitor, CancellationToken token) => throw new NotSupportedException();
        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => throw new NotSupportedException();
    }
}
