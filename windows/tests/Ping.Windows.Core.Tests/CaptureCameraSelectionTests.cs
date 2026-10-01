using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class CaptureCameraSelectionTests
{
    [Fact]
    public async Task PreviewAndRecordingResolveOneOpaqueIdentityPerLease()
    {
        using var lease = new CameraOwnership().TryAcquire(CameraPurpose.Manual)!;
        var ready = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        var preview = lease.CameraSelection.GetAsync(_ => { calls++; return ready.Task; });
        var recording = lease.CameraSelection.GetAsync(_ => throw new Exception("must reuse selection"));
        ready.SetResult(@"\\?\fixture#camera#{opaque-id}");
        Assert.Equal(await preview, await recording);
        Assert.Equal(1, calls);
    }

    [Fact]
    public async Task NewLeaseCanChooseChangedDevice()
    {
        var ownership = new CameraOwnership();
        using (var first = ownership.TryAcquire(CameraPurpose.Manual)!)
            Assert.Equal("first", await first.CameraSelection.GetAsync(_ => Task.FromResult("first")));
        using var next = ownership.TryAcquire(CameraPurpose.Manual)!;
        Assert.Equal("next", await next.CameraSelection.GetAsync(_ => Task.FromResult("next")));
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("fixture\0other")]
    public async Task InvalidIdentityCannotFallBackToAnUnselectedCamera(string id)
    {
        using var lease = new CameraOwnership().TryAcquire(CameraPurpose.Manual)!;
        await Assert.ThrowsAsync<InvalidOperationException>(() => lease.CameraSelection.GetAsync(_ => Task.FromResult(id)));
    }

    [Fact]
    public async Task CancellationWaitsActualEnumerationCompletion()
    {
        using var lease = new CameraOwnership().TryAcquire(CameraPurpose.Manual)!;
        using var cancellation = new CancellationTokenSource();
        var ready = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = lease.CameraSelection.GetAsync(_ => ready.Task, cancellation.Token);
        cancellation.Cancel();
        Assert.False(pending.IsCompleted);
        ready.SetResult("fixture");
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
        Assert.Equal("fixture", await lease.CameraSelection.GetAsync(_ => throw new Exception("must reuse completed choice")));
    }

    [Fact]
    public async Task ClosedLeaseCannotEnumerateOrReuseDevice()
    {
        var lease = new CameraOwnership().TryAcquire(CameraPurpose.Manual)!;
        Assert.Equal("fixture", await lease.CameraSelection.GetAsync(_ => Task.FromResult("fixture")));
        lease.Dispose();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => lease.CameraSelection.GetAsync(_ => throw new Exception("must not enumerate")));
    }
}
