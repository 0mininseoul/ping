using Ping.Windows.Core.Incoming;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class StartupIdentityGateTests
{
    [Fact]
    public async Task ColdNotificationWaitsForIdentityInsteadOfSilentlyDroppingPlayback()
    {
        var gate = new StartupIdentityGate();
        var notification = gate.WaitAsync();
        Assert.False(notification.IsCompleted);
        gate.SetReady("me");
        Assert.Equal("me", await notification);
    }

    [Fact]
    public async Task CancelledActivationDoesNotCancelOtherWaiters()
    {
        var gate = new StartupIdentityGate();
        using var cancellation = new CancellationTokenSource();
        var cancelled = gate.WaitAsync(cancellation.Token);
        var other = gate.WaitAsync();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => cancelled);
        gate.SetReady("me");
        Assert.Equal("me", await other);
    }

    [Fact]
    public async Task PermanentStartupFailureCompletesWaitersAndExplicitRetryCreatesFreshGate()
    {
        var gate = new StartupIdentityGate();
        var waiting = gate.WaitAsync();
        gate.Fail(new IOException("fixture"));
        await Assert.ThrowsAsync<IOException>(() => waiting);
        gate.PrepareRetry();
        var retry = gate.WaitAsync();
        Assert.False(retry.IsCompleted);
        gate.SetReady("me");
        Assert.Equal("me", await retry);
    }
}
