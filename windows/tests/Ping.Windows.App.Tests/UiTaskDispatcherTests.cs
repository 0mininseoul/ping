using Ping.Windows.App.History;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class UiTaskDispatcherTests
{
    [Fact]
    public async Task BackgroundWorkWaitsForUiQueueBeforeTouchingViewModel()
    {
        var queued = new Queue<Action>();
        var hasAccess = false;
        var ran = false;
        var dispatcher = new UiTaskDispatcher(() => hasAccess, action => { queued.Enqueue(action); return true; });
        var result = dispatcher.RunAsync(() => { Assert.True(hasAccess); ran = true; return Task.FromResult(42); });
        Assert.False(ran);
        Assert.False(result.IsCompleted);
        hasAccess = true;
        Assert.Single(queued)();
        Assert.Equal(42, await result);
    }

    [Fact]
    public async Task ClosedQueueDoesNotRunWindowWork()
    {
        var dispatcher = new UiTaskDispatcher(() => false, _ => false);
        await Assert.ThrowsAsync<OperationCanceledException>(() => dispatcher.RunAsync<int>(() => throw new InvalidOperationException("must not execute")));
    }

    [Fact]
    public async Task WorkFailurePropagatesFromUiQueue()
    {
        Action? queued = null;
        var dispatcher = new UiTaskDispatcher(() => false, action => { queued = action; return true; });
        var task = dispatcher.RunAsync<int>(() => throw new HttpRequestException("offline"));
        queued!();
        await Assert.ThrowsAsync<HttpRequestException>(() => task);
    }
}
