using System.Collections.Concurrent;
using System.Text.Json;
using System.Threading.Channels;
using Ping.Windows.Core.Realtime;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class RealtimeConnectionTests
{
    private static readonly RealtimeConnectionOptions Fast = new(TimeSpan.FromMilliseconds(100), TimeSpan.FromMilliseconds(40), TimeSpan.FromMilliseconds(100));

    [Fact]
    public async Task ConnectionWaitsForJoinThenDispatchesScopedInvalidation()
    {
        await using var socket = new FakeRealtimeTransport();
        var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var received = new TaskCompletionSource<RealtimeChange>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var cancel = new CancellationTokenSource();
        var connection = new RealtimeConnection(socket, Fast);
        var running = connection.RunAsync(RealtimeProtocol.Channels("me", ["room"]), Credentials(), _ => Task.FromResult(Credentials()),
            () => ready.TrySetResult(), (change, _) => { received.TrySetResult(change); return Task.CompletedTask; }, cancel.Token);
        await ready.Task.WaitAsync(TimeSpan.FromSeconds(3));
        socket.Push("""{"event":"postgres_changes","topic":"realtime:chat-room-room","payload":{"data":{"schema":"public","table":"chat_messages","type":"INSERT","record":{"id":"new","room_id":"room"}}}}""");
        Assert.Equal("new", (await received.Task.WaitAsync(TimeSpan.FromSeconds(3))).ItemId);
        cancel.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => running);
    }

    [Fact]
    public async Task HeartbeatRenewalReadsLatestSessionToken()
    {
        await using var socket = new FakeRealtimeTransport();
        using var cancel = new CancellationTokenSource();
        var running = new RealtimeConnection(socket, Fast).RunAsync(RealtimeProtocol.Channels("me", []), Credentials(),
            _ => Task.FromResult(Credentials("renewed")), () => { }, (_, _) => Task.CompletedTask, cancel.Token);
        await socket.TokenUpdated.Task.WaitAsync(TimeSpan.FromSeconds(3));
        using var update = JsonDocument.Parse(Assert.Single(socket.Sent, frame => frame.Contains("\"access_token\",", StringComparison.Ordinal)));
        Assert.Equal("renewed", update.RootElement.GetProperty("payload").GetProperty("access_token").GetString());
        cancel.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => running);
    }

    [Theory]
    [InlineData(true, false)]
    [InlineData(false, true)]
    public async Task MissingJoinOrHeartbeatAcknowledgementTerminatesConnection(bool dropJoins, bool dropHeartbeat)
    {
        await using var socket = new FakeRealtimeTransport { DropJoins = dropJoins, DropHeartbeats = dropHeartbeat };
        using var cancel = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await Assert.ThrowsAsync<TimeoutException>(() => new RealtimeConnection(socket, Fast).RunAsync(RealtimeProtocol.Channels("me", []),
            Credentials(), _ => Task.FromResult(Credentials()), () => { }, (_, _) => Task.CompletedTask, cancel.Token));
    }

    [Fact]
    public async Task SubscriptionRejectionDoesNotReportReadyOrLeakServerPayload()
    {
        await using var socket = new FakeRealtimeTransport { RejectJoins = true };
        var ready = false;
        var error = await Assert.ThrowsAsync<RealtimeProtocolException>(() => new RealtimeConnection(socket, Fast).RunAsync(
            RealtimeProtocol.Channels("me", []), Credentials(), _ => Task.FromResult(Credentials()), () => ready = true, (_, _) => Task.CompletedTask));
        Assert.False(ready);
        Assert.DoesNotContain("SECRET", error.ToString());
    }

    [Fact]
    public async Task SlowRpcCallbackCannotPreventHeartbeatReception()
    {
        await using var socket = new FakeRealtimeTransport();
        using var cancel = new CancellationTokenSource();
        var callbackEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var running = new RealtimeConnection(socket, Fast).RunAsync(RealtimeProtocol.Channels("me", []), Credentials(), _ => Task.FromResult(Credentials()),
            () => ready.TrySetResult(), async (_, token) => { callbackEntered.TrySetResult(); await Task.Delay(Timeout.Infinite, token); }, cancel.Token);
        await ready.Task.WaitAsync(TimeSpan.FromSeconds(3));
        socket.Push("""{"event":"postgres_changes","topic":"realtime:incoming-video-me","payload":{"data":{"schema":"public","table":"messages","type":"INSERT","record":{"id":"new"}}}}""");
        await callbackEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await socket.SecondHeartbeat.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Assert.False(running.IsCompleted);
        cancel.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => running);
    }

    [Fact]
    public async Task ChangedIdentityStopsTokenPushToPreviousUsersChannels()
    {
        await using var socket = new FakeRealtimeTransport();
        var changed = new RealtimeCredentials(new Uri("https://fixture.supabase.co"), "anon", "other-token", "other");
        await Assert.ThrowsAsync<RealtimeIdentityChangedException>(() => new RealtimeConnection(socket, Fast).RunAsync(RealtimeProtocol.Channels("me", []),
            Credentials(), _ => Task.FromResult(changed), () => { }, (_, _) => Task.CompletedTask));
        Assert.DoesNotContain(socket.Sent, frame => frame.Contains("other-token", StringComparison.Ordinal));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task StalledConnectOrSendHasDeadlineAndCancelsTransportWork(bool connect)
    {
        await using var socket = new FakeRealtimeTransport { StallConnect = connect, StallSends = !connect };
        using var cancel = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await Assert.ThrowsAsync<TimeoutException>(() => new RealtimeConnection(socket, Fast).RunAsync(
            RealtimeProtocol.Channels("me", []), Credentials(), _ => Task.FromResult(Credentials()), () => { }, (_, _) => Task.CompletedTask, cancel.Token));
        Assert.True(socket.StalledWorkCancelled);
    }

    [Fact]
    public async Task StalledCredentialRenewalHasDeadline()
    {
        await using var socket = new FakeRealtimeTransport();
        using var cancel = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        await Assert.ThrowsAsync<TimeoutException>(() => new RealtimeConnection(socket, Fast).RunAsync(
            RealtimeProtocol.Channels("me", []), Credentials(), async token =>
            {
                await Task.Delay(Timeout.Infinite, token);
                return Credentials();
            }, () => { }, (_, _) => Task.CompletedTask, cancel.Token));
    }

    private static RealtimeCredentials Credentials(string token = "initial") => new(new Uri("https://fixture.supabase.co"), "anon", token, "me");
}

internal sealed class FakeRealtimeTransport : IRealtimeTransport
{
    private readonly Channel<string> received = Channel.CreateUnbounded<string>();
    public ConcurrentQueue<string> Sent { get; } = new();
    public bool DropJoins;
    public bool RejectJoins;
    public bool DropHeartbeats;
    public int Heartbeats;
    public bool Disposed;
    public bool StallConnect;
    public bool StallSends;
    public bool StalledWorkCancelled;
    public TaskCompletionSource TokenUpdated { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public TaskCompletionSource SecondHeartbeat { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
    public void Push(string message) => received.Writer.TryWrite(message);
    public Task ConnectAsync(Uri endpoint, string anonKey, string token, CancellationToken cancellationToken) => StallConnect ? StallAsync(cancellationToken) : Task.CompletedTask;
    public async Task SendAsync(string text, CancellationToken cancellationToken)
    {
        if (StallSends) { await StallAsync(cancellationToken); return; }
        Sent.Enqueue(text);
        using var document = JsonDocument.Parse(text);
        var root = document.RootElement;
        var eventName = root.GetProperty("event").GetString();
        var topic = root.GetProperty("topic").GetString();
        var reference = root.GetProperty("ref").GetString();
        if (eventName == "phx_join" && !DropJoins)
        {
            var filters = root.GetProperty("payload").GetProperty("config").GetProperty("postgres_changes").EnumerateArray()
                .Select((filter, index) => new { id = index + 1, @event = filter.GetProperty("event").GetString(), schema = "public", table = filter.GetProperty("table").GetString() }).ToArray();
            Push(JsonSerializer.Serialize(new { @event = "phx_reply", topic, @ref = reference, payload = new { status = RejectJoins ? "error" : "ok", response = new { postgres_changes = filters, message = "SECRET server payload" } } }));
        }
        if (eventName == "access_token") TokenUpdated.TrySetResult();
        if (eventName == "heartbeat")
        {
            if (Interlocked.Increment(ref Heartbeats) >= 2) SecondHeartbeat.TrySetResult();
            if (!DropHeartbeats) Push(JsonSerializer.Serialize(new { @event = "phx_reply", topic, @ref = reference, payload = new { status = "ok", response = new { } } }));
        }
    }
    private async Task StallAsync(CancellationToken token)
    {
        try { await Task.Delay(Timeout.Infinite, token); }
        finally { StalledWorkCancelled = token.IsCancellationRequested; }
    }
    public async Task<string?> ReceiveAsync(CancellationToken cancellationToken) => await received.Reader.ReadAsync(cancellationToken);
    public ValueTask DisposeAsync() { Disposed = true; received.Writer.TryComplete(); return ValueTask.CompletedTask; }
}
