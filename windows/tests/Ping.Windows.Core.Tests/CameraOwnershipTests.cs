using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class CameraOwnershipTests
{
    [Fact]
    public void LeaseIsExclusiveAndDisposalIsIdempotent()
    {
        var camera = new CameraOwnership();
        var lease = Assert.IsType<CameraLease>(camera.TryAcquire(CameraPurpose.Manual));
        Assert.True(camera.IsBusy);
        Assert.Null(camera.TryAcquire(CameraPurpose.AutomaticReply));
        Assert.Null(camera.TryAcquire(CameraPurpose.Manual));
        lease.Dispose();
        lease.Dispose();
        Assert.False(camera.IsBusy);
        using var next = camera.TryAcquire(CameraPurpose.AutomaticReply);
        Assert.NotNull(next);
    }

    [Fact]
    public async Task UserPreemptsAutomaticButWaitsForCameraCleanup()
    {
        var camera = new CameraOwnership();
        using var automatic = camera.TryAcquire(CameraPurpose.AutomaticReply)!;
        var grant = camera.AcquireManualAsync();
        Assert.True(automatic.Token.IsCancellationRequested);
        Assert.False(grant.IsCompleted);
        Assert.Null(camera.TryAcquire(CameraPurpose.AutomaticReply));
        automatic.Dispose();
        using var manual = await grant;
        Assert.NotNull(manual);
        Assert.Equal(CameraPurpose.Manual, manual.Purpose);
        Assert.Null(await camera.AcquireManualAsync());
    }

    [Fact]
    public async Task CancelledUserWaitDoesNotReleaseLiveAutomaticOwner()
    {
        var camera = new CameraOwnership();
        using var automatic = camera.TryAcquire(CameraPurpose.AutomaticReply)!;
        using var cancellation = new CancellationTokenSource();
        var grant = camera.AcquireManualAsync(cancellation.Token);
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => grant);
        Assert.True(camera.IsBusy);
        automatic.Dispose();
        using var next = camera.TryAcquire(CameraPurpose.AutomaticReply);
        Assert.NotNull(next);
    }

    [Fact]
    public void InterruptDoesNotCancelUserCapture()
    {
        var camera = new CameraOwnership();
        using var manual = camera.TryAcquire(CameraPurpose.Manual)!;
        camera.InterruptAutomatic();
        Assert.False(manual.Token.IsCancellationRequested);
    }
}
