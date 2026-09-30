using System.Collections.Concurrent;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Realtime;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class RealtimeSupervisorTests
{
    [Fact]
    public async Task SameRoomSetReusesConnectionButReplacementDisposesPreviousOwner()
    {
        var sockets = new ConcurrentQueue<FakeRealtimeTransport>();
        await using var supervisor = new RealtimeSupervisor(_ => Task.FromResult(Credentials()), (_, _) => Task.CompletedTask,
            transportFactory: () => { var socket = new FakeRealtimeTransport(); sockets.Enqueue(socket); return socket; });
        await supervisor.UpdateAsync("me", ["a", "b"]);
        await WaitUntilAsync(() => supervisor.State == RealtimeConnectionState.Connected);
        await supervisor.UpdateAsync("me", ["b", "a", "a"]);
        Assert.Single(sockets);
        await supervisor.UpdateAsync("me", ["c"]);
        await WaitUntilAsync(() => supervisor.State == RealtimeConnectionState.Connected && sockets.Count == 2);
        Assert.True(sockets.First().Disposed);
        Assert.False(sockets.Last().Disposed);
    }

    [Fact]
    public async Task DroppedSocketFallsBackAndReconnectsWithLatestCredentials()
    {
        var sockets = new ConcurrentQueue<FakeRealtimeTransport>();
        var connections = 0;
        var fallbacks = 0;
        await using var supervisor = new RealtimeSupervisor(_ => Task.FromResult(Credentials("token-" + Interlocked.Increment(ref connections))),
            (_, _) => Task.CompletedTask,
            transportFactory: () => { var socket = new FakeRealtimeTransport(); sockets.Enqueue(socket); return socket; },
            delayAsync: (_, token) => Task.Delay(1, token));
        supervisor.StateChanged += state => { if (state == RealtimeConnectionState.FallbackPolling) Interlocked.Increment(ref fallbacks); };
        await supervisor.UpdateAsync("me", []);
        await WaitUntilAsync(() => supervisor.State == RealtimeConnectionState.Connected);
        sockets.First().Push("[]");
        await WaitUntilAsync(() => sockets.Count >= 2 && supervisor.State == RealtimeConnectionState.Connected);
        Assert.True(fallbacks > 0);
        Assert.Contains(sockets.Last().Sent, message => message.Contains("token-2", StringComparison.Ordinal));
        Assert.True(sockets.First().Disposed);
    }

    [Fact]
    public async Task CancellationWhileJoiningDisposesSocketAndStopsCallbacks()
    {
        var socket = new FakeRealtimeTransport { DropJoins = true };
        var changes = 0;
        var supervisor = new RealtimeSupervisor(_ => Task.FromResult(Credentials()), (_, _) => { Interlocked.Increment(ref changes); return Task.CompletedTask; }, transportFactory: () => socket);
        await supervisor.UpdateAsync("me", []);
        await WaitUntilAsync(() => socket.Sent.Count > 0);
        await supervisor.DisposeAsync();
        socket.Push("invalid-after-disposal");
        Assert.True(socket.Disposed);
        Assert.Equal(RealtimeConnectionState.Stopped, supervisor.State);
        Assert.Equal(0, changes);
    }

    [Fact]
    public async Task BackoffIsBoundedAndCancellationInterruptsIt()
    {
        var delays = new ConcurrentQueue<TimeSpan>();
        var reached = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var supervisor = new RealtimeSupervisor(_ => Task.FromResult(Credentials()), (_, _) => Task.CompletedTask,
            transportFactory: () => new FakeRealtimeTransport { RejectJoins = true },
            delayAsync: async (duration, token) =>
            {
                delays.Enqueue(duration);
                if (delays.Count >= 8) { reached.TrySetResult(); await Task.Delay(Timeout.Infinite, token); }
            }, jitter: () => 0);
        await supervisor.UpdateAsync("me", []);
        await reached.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await supervisor.DisposeAsync();
        Assert.Equal(new[] { 1, 2, 5, 10, 30, 60, 60, 60 }, delays.Select(delay => (int)delay.TotalSeconds));
    }

    [Fact]
    public async Task RejectedSessionRemainsStoppedUntilExplicitRecovery()
    {
        var calls = 0;
        var sockets = new ConcurrentQueue<FakeRealtimeTransport>();
        await using var supervisor = new RealtimeSupervisor(_ => Interlocked.Increment(ref calls) == 1
            ? Task.FromException<RealtimeCredentials>(new SupabaseSessionExpiredException("me", new Exception("fixture")))
            : Task.FromResult(Credentials()), (_, _) => Task.CompletedTask,
            transportFactory: () => { var socket = new FakeRealtimeTransport(); sockets.Enqueue(socket); return socket; });
        await supervisor.UpdateAsync("me", []);
        await WaitUntilAsync(() => supervisor.State == RealtimeConnectionState.RecoveryRequired);
        await supervisor.UpdateAsync("me", []);
        Assert.Equal(1, calls);
        Assert.Empty(sockets);
        await supervisor.UpdateAsync("me", [], forceReconnect: true);
        await WaitUntilAsync(() => supervisor.State == RealtimeConnectionState.Connected);
        Assert.Single(sockets);
    }

    [Fact]
    public async Task DifferentAccountCredentialsNeverCreateOldAccountSocket()
    {
        var transports = 0;
        await using var supervisor = new RealtimeSupervisor(_ => Task.FromResult(new RealtimeCredentials(new Uri("https://fixture.supabase.co"), "anon", "other", "other")),
            (_, _) => Task.CompletedTask, transportFactory: () => { Interlocked.Increment(ref transports); return new FakeRealtimeTransport(); });
        await supervisor.UpdateAsync("me", []);
        await WaitUntilAsync(() => supervisor.State == RealtimeConnectionState.RecoveryRequired);
        Assert.Equal(0, transports);
    }

    private static RealtimeCredentials Credentials(string token = "initial") => new(new Uri("https://fixture.supabase.co"), "anon", token, "me");
    private static async Task WaitUntilAsync(Func<bool> condition)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        while (!condition()) await Task.Delay(5, timeout.Token);
    }
}
