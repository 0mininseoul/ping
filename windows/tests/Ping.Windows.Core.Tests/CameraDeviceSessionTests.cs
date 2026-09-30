using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class CameraDeviceSessionTests
{
    [Fact]
    public async Task PreviewAndRecordingReuseOneInitializedDeviceSerially()
    {
        var owner = new CameraOwnership();
        using var lease = owner.TryAcquire(CameraPurpose.Manual)!;
        var initializes = 0;
        var disposed = 0;
        await using var session = new CameraDeviceSession<object>(lease,
            _ => { ++initializes; return Task.FromResult(new object()); }, _ => { ++disposed; return ValueTask.CompletedTask; });
        var first = await session.UseAsync((device, _) => Task.FromResult(device));
        var second = await session.UseAsync((device, _) => Task.FromResult(device));
        Assert.Same(first, second);
        Assert.Equal(1, initializes);
        Assert.Equal(0, disposed);
        await session.DisposeAsync();
        Assert.Equal(1, disposed);
        Assert.True(owner.IsBusy);
        lease.Dispose();
        Assert.False(owner.IsBusy);
    }

    [Fact]
    public async Task CloseDuringUncooperativeInitializationAwaitsAndDisposesDevice()
    {
        using var lease = new CameraOwnership().TryAcquire(CameraPurpose.Manual)!;
        var initializing = new TaskCompletionSource<object>(TaskCreationOptions.RunContinuationsAsynchronously);
        var used = false;
        var disposed = false;
        var session = new CameraDeviceSession<object>(lease, _ => initializing.Task,
            _ => { disposed = true; return ValueTask.CompletedTask; });
        var preview = session.UseAsync((device, _) => { used = true; return Task.FromResult(true); });
        var close = session.DisposeAsync().AsTask();
        Assert.False(close.IsCompleted);
        initializing.SetResult(new object());
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => preview);
        await close;
        Assert.True(disposed);
        Assert.False(used);
    }

    [Fact]
    public async Task CloseCancelsRecordingButDoesNotDisposeDeviceUntilRecordingCleanupFinishes()
    {
        using var lease = new CameraOwnership().TryAcquire(CameraPurpose.Manual)!;
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var cleanup = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var disposed = false;
        var session = new CameraDeviceSession<object>(lease, _ => Task.FromResult(new object()),
            _ => { disposed = true; return ValueTask.CompletedTask; });
        var record = session.UseAsync(async (_, token) =>
        {
            started.SetResult();
            try { await Task.Delay(Timeout.InfiniteTimeSpan, token); }
            finally { await cleanup.Task; }
            return true;
        });
        await started.Task;
        var close = session.DisposeAsync().AsTask();
        Assert.False(disposed);
        Assert.False(close.IsCompleted);
        cleanup.SetResult();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => record);
        await close;
        Assert.True(disposed);
        await session.DisposeAsync();
    }

    [Fact]
    public async Task OperationsNeverOverlapAndClosedSessionCannotReinitialize()
    {
        using var lease = new CameraOwnership().TryAcquire(CameraPurpose.Manual)!;
        var session = new CameraDeviceSession<object>(lease, _ => Task.FromResult(new object()), _ => ValueTask.CompletedTask);
        var firstWork = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var secondEntered = false;
        var first = session.UseAsync(async (_, _) => { await firstWork.Task; return 1; });
        var second = session.UseAsync((_, _) => { secondEntered = true; return Task.FromResult(2); });
        Assert.False(secondEntered);
        firstWork.SetResult();
        Assert.Equal(1, await first);
        Assert.Equal(2, await second);
        await session.DisposeAsync();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => session.UseAsync((_, _) => Task.FromResult(3)));
    }
}
