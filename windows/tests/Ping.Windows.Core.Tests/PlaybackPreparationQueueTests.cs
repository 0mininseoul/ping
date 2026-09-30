using System.Collections.Concurrent;
using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class PlaybackPreparationQueueTests
{
    [Fact]
    public async Task DuplicatePendingRequestsSharePreparationAndClickUpgradesArrivalSource()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var prepares = 0;
        var sources = new List<IncomingArrivalSource>();
        await using var queue = new PlaybackPreparationQueue(async (_, token) =>
        {
            prepares++;
            entered.TrySetResult();
            await release.Task.WaitAsync(token);
            return "fixture.mp4";
        }, (_, _, _, source, _) => { sources.Add(source); return Task.CompletedTask; });
        var automatic = queue.RequestAsync("me", Video("same"), IncomingArrivalSource.Live);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var click = queue.RequestAsync("me", Video("same"), IncomingArrivalSource.NotificationClick);
        release.TrySetResult();
        await Task.WhenAll(automatic, click);
        Assert.Equal(1, prepares);
        Assert.Equal(new[] { IncomingArrivalSource.NotificationClick }, sources);
    }

    [Fact]
    public async Task PreparationConcurrencyIsBoundedAndAnItemFailureDoesNotBlockOthers()
    {
        var active = 0;
        var maximum = 0;
        var presented = new ConcurrentQueue<string>();
        await using var queue = new PlaybackPreparationQueue(async (message, token) =>
        {
            var count = Interlocked.Increment(ref active);
            maximum = Math.Max(maximum, count);
            try { await Task.Delay(30, token); if (message.Id == "bad") throw new IOException("fixture"); return "fixture.mp4"; }
            finally { Interlocked.Decrement(ref active); }
        }, (_, message, _, _, _) => { presented.Enqueue(message.Id!); return Task.CompletedTask; }, maximumConcurrency: 2, retryDelay: TimeSpan.Zero);
        var bad = queue.RequestAsync("me", Video("bad"), IncomingArrivalSource.Live);
        var good = Enumerable.Range(0, 8).Select(index => queue.RequestAsync("me", Video(index.ToString()), IncomingArrivalSource.Live)).ToArray();
        await Task.WhenAll(good);
        await Assert.ThrowsAsync<IOException>(() => bad);
        Assert.InRange(maximum, 1, 2);
        Assert.Equal(8, presented.Count);
    }

    [Fact]
    public async Task LifetimeCancellationAwaitsDownloadsAndDoesNotPresentCancelledWork()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var cancelled = false;
        var presented = false;
        var queue = new PlaybackPreparationQueue(async (_, token) =>
        {
            entered.TrySetResult();
            try { await Task.Delay(Timeout.Infinite, token); return "fixture.mp4"; }
            finally { cancelled = token.IsCancellationRequested; }
        }, (_, _, _, _, _) => { presented = true; return Task.CompletedTask; });
        var request = queue.RequestAsync("me", Video("pending"), IncomingArrivalSource.Live);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await queue.DisposeAsync();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => request);
        Assert.True(cancelled);
        Assert.False(presented);
    }

    private static VideoMessage Video(string id) => new()
    {
        Id = id, RoomId = "room", SenderUid = "peer", ReceiverUid = "me", SenderNickname = "Peer", VideoId = id,
        VideoUrl = "peer/" + id + ".mp4", DurationMs = 3000, MirrorPosition = new(.5, .5), Status = MessageStatus.Uploaded,
        CreatedAt = DateTimeOffset.UtcNow, ExpiresAt = DateTimeOffset.UtcNow.AddDays(1)
    };
}
