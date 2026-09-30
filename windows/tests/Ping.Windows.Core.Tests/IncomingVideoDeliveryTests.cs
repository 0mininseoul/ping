using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class IncomingVideoDeliveryTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-30T09:00:00Z");

    [Fact]
    public async Task NotificationFailureRemainsRetryableAndNeverAcknowledgesServer()
    {
        var notifications = 0;
        var ack = 0;
        var playback = 0;
        var delivery = Create((_, _) => Task.FromResult(++notifications == 1 ? IncomingNotificationResult.Unavailable : IncomingNotificationResult.Shown),
            (_, _, _) => { playback++; return Task.CompletedTask; }, (_, _) => { ack++; return Task.CompletedTask; });
        await Assert.ThrowsAsync<IncomingDeliveryException>(() => delivery.DeliverAsync("me", Video(), IncomingArrivalSource.Live));
        Assert.Equal(0, ack);
        await delivery.DeliverAsync("me", Video(), IncomingArrivalSource.Live);
        await delivery.DeliverAsync("me", Video(), IncomingArrivalSource.Live);
        Assert.Equal(2, notifications);
        Assert.Equal(1, ack);
        Assert.Equal(1, playback);
    }

    [Fact]
    public async Task AcknowledgementFailureDoesNotRepeatPlaybackAndRetriesSeparately()
    {
        var calls = new List<string>();
        var failAck = true;
        var delivery = Create((_, _) => { calls.Add("notify"); return Task.FromResult(IncomingNotificationResult.Shown); },
            (_, _, _) => { calls.Add("playback"); return Task.CompletedTask; }, (_, _) =>
            {
                calls.Add("ack");
                if (failAck) throw new IOException("fixture");
                return Task.CompletedTask;
            });
        await delivery.DeliverAsync("me", Video(), IncomingArrivalSource.Live);
        await delivery.DeliverAsync("me", Video(), IncomingArrivalSource.Live);
        failAck = false;
        await delivery.RetryAcknowledgementsAsync("me");
        await delivery.RetryAcknowledgementsAsync("me");
        Assert.Equal(new[] { "notify", "playback", "ack", "ack" }, calls);
    }

    [Theory]
    [InlineData(IncomingArrivalSource.StartupCatchUp, IncomingNotificationResult.Shown)]
    [InlineData(IncomingArrivalSource.ReconnectCatchUp, IncomingNotificationResult.Shown)]
    [InlineData(IncomingArrivalSource.Live, IncomingNotificationResult.Duplicate)]
    public async Task CatchUpAndPersistedDuplicatesDoNotAutoPlay(IncomingArrivalSource source, IncomingNotificationResult result)
    {
        var playback = 0;
        var delivery = Create((_, _) => Task.FromResult(result), (_, _, _) => { playback++; return Task.CompletedTask; }, (_, _) => Task.CompletedTask);
        await delivery.DeliverAsync("me", Video(), source);
        Assert.Equal(0, playback);
    }

    [Theory]
    [InlineData(IncomingArrivalSource.StartupCatchUp)]
    [InlineData(IncomingArrivalSource.ReconnectCatchUp)]
    public async Task FailedCatchUpNotificationKeepsOriginalSourceWhenRetriedByLivePolling(IncomingArrivalSource source)
    {
        var notifications = 0;
        var playback = 0;
        var delivery = Create((_, _) => Task.FromResult(++notifications == 1 ? IncomingNotificationResult.Unavailable : IncomingNotificationResult.Shown),
            (_, _, _) => { playback++; return Task.CompletedTask; }, (_, _) => Task.CompletedTask);
        await Assert.ThrowsAsync<IncomingDeliveryException>(() => delivery.DeliverAsync("me", Video(), source));
        await delivery.DeliverAsync("me", Video(), IncomingArrivalSource.Live);
        Assert.Equal(2, notifications);
        Assert.Equal(0, playback);
    }

    private static IncomingVideoDelivery Create(Func<VideoMessage, CancellationToken, Task<IncomingNotificationResult>> notify,
        Func<VideoMessage, IncomingArrivalSource, CancellationToken, Task> playback, Func<string, CancellationToken, Task> acknowledge) =>
        new(Now.AddMinutes(-5), () => true, notify, playback, acknowledge, now: () => Now);

    private static VideoMessage Video() => new()
    {
        Id = "video", RoomId = "room", SenderUid = "peer", ReceiverUid = "me", SenderNickname = "Peer", VideoId = "file",
        VideoUrl = "peer/file.mp4", DurationMs = 3000, MirrorPosition = new(.5, .5), Status = MessageStatus.Uploaded,
        CreatedAt = Now.AddSeconds(-2), ExpiresAt = Now.AddDays(1)
    };
}
