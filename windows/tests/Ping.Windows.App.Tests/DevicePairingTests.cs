using Ping.Windows.App.Setup;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class DevicePairingTests
{
    [Fact]
    public async Task ClosingPaneDiscardsLateQrAndCancelsItsRequest()
    {
        var finished = new TaskCompletionSource<PairingQrImage>();
        CancellationToken active = default;
        var model = new DevicePairingViewModel(token => { active = token; return finished.Task; }, () => "me");
        var pending = model.OpenAsync();
        model.Deactivate();
        Assert.True(active.IsCancellationRequested);
        finished.SetResult(new([1], "me", DateTimeOffset.UtcNow.AddHours(1)));
        await pending;
        Assert.Null(model.Image);
        Assert.False(model.IsActive);
    }
    [Fact]
    public async Task AccountChangeCannotDisplayPreviousAccountQr()
    {
        var finished = new TaskCompletionSource<PairingQrImage>();
        var uid = "previous";
        var model = new DevicePairingViewModel(_ => finished.Task, () => uid);
        var pending = model.OpenAsync();
        uid = "current";
        finished.SetResult(new([1], "previous", DateTimeOffset.UtcNow.AddHours(1)));
        await pending;
        Assert.Null(model.Image);
        Assert.Contains("계정", model.Status);
    }
    [Fact]
    public async Task FailureShowsSafeRetryMessageAndRetryUsesLatestSession()
    {
        var calls = 0;
        var model = new DevicePairingViewModel(_ => ++calls == 1
            ? throw new InvalidOperationException("fixture-token-must-not-appear")
            : Task.FromResult(new PairingQrImage([1], "me", DateTimeOffset.UtcNow.AddHours(1))), () => "me");
        await model.OpenAsync();
        Assert.Null(model.Image);
        Assert.DoesNotContain("fixture-token", model.Status);
        await model.OpenAsync();
        Assert.NotNull(model.Image);
        Assert.Equal(2, calls);
        model.Deactivate();
        Assert.Null(model.Image);
    }
}
