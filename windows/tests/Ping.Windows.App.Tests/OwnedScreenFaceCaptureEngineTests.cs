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
}
