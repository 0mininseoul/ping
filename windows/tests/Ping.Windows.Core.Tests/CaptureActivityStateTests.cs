using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class CaptureActivityStateTests
{
    [Fact]
    public void ResumeNeverErasesAnInterruptionForInFlightWork()
    {
        var state = new CaptureActivityState();
        var generation = state.Generation;
        var events = 0;
        state.Interrupted += () => ++events;
        state.SetDisplayAwake(false);
        state.SetDisplayAwake(true);
        Assert.False(state.IsBlocked);
        Assert.True(state.WasInterruptedSince(generation));
        Assert.Equal(1, events);
        var afterWake = state.Generation;
        state.SetDisplayAwake(true);
        Assert.False(state.WasInterruptedSince(afterWake));
    }

    [Fact]
    public void LockAndSuspendRemainBlockedUntilEveryConditionClears()
    {
        var state = new CaptureActivityState();
        state.SetLocked(true);
        state.SetSuspended(true);
        state.SetLocked(false);
        Assert.True(state.IsBlocked);
        state.SetSuspended(false);
        Assert.False(state.IsBlocked);
    }
}
