using System.Net;
using System.Threading.Channels;
using Ping.Windows.Core.Backend;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class ConnectionSupervisorTests
{
    [Fact]
    public async Task TemporaryFailureRetriesAndBecomesConnected()
    {
        var calls = 0;
        var delays = new List<TimeSpan>();
        await using var supervisor = new ConnectionSupervisor(_ =>
        {
            if (++calls == 1) throw new HttpRequestException("offline");
            return Task.CompletedTask;
        }, (delay, _) => { delays.Add(delay); return Task.CompletedTask; }, () => 0.5);
        var states = Observe(supervisor);

        supervisor.Start();
        await ReadUntilAsync(states, ConnectionState.Connected);

        Assert.Equal(2, calls);
        Assert.Equal([TimeSpan.FromSeconds(1)], delays);
    }

    [Fact]
    public async Task RetryLadderCapsAtSixtySecondsAndResetsAfterSuccess()
    {
        var calls = 0;
        var delays = new List<TimeSpan>();
        await using var supervisor = new ConnectionSupervisor(_ =>
        {
            if (++calls <= 8 || calls == 10) throw new HttpRequestException("offline");
            return Task.CompletedTask;
        }, (delay, _) => { delays.Add(delay); return Task.CompletedTask; }, () => 0.5);
        var states = Observe(supervisor);
        supervisor.Start();
        await ReadUntilAsync(states, ConnectionState.Connected);
        supervisor.RequestReconnect();
        await ReadUntilAsync(states, ConnectionState.Connected);

        Assert.Equal(new[] { 1, 2, 5, 10, 30, 60, 60, 60, 1 }, delays.Select(delay => (int)delay.TotalSeconds));
    }

    [Fact]
    public async Task RetryAfterHeaderIsRespected()
    {
        var calls = 0;
        TimeSpan? actualDelay = null;
        await using var supervisor = new ConnectionSupervisor(_ =>
        {
            if (++calls == 1) throw new SupabaseRequestException(HttpStatusCode.TooManyRequests, [], TimeSpan.FromSeconds(120));
            return Task.CompletedTask;
        }, (delay, _) => { actualDelay = delay; return Task.CompletedTask; }, () => 0.5);
        var states = Observe(supervisor);
        supervisor.Start();
        await ReadUntilAsync(states, ConnectionState.Connected);

        Assert.Equal(TimeSpan.FromSeconds(120), actualDelay);
    }

    [Fact]
    public async Task ReconnectInterruptsPendingBackoff()
    {
        var delayed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        await using var supervisor = new ConnectionSupervisor(_ =>
        {
            if (++calls == 1) throw new HttpRequestException("offline");
            return Task.CompletedTask;
        }, async (_, token) => { delayed.SetResult(); await Task.Delay(Timeout.InfiniteTimeSpan, token); });
        var states = Observe(supervisor);
        supervisor.Start();
        await delayed.Task.WaitAsync(TimeSpan.FromSeconds(3));

        supervisor.RequestReconnect();
        await ReadUntilAsync(states, ConnectionState.Connected);

        Assert.Equal(2, calls);
    }

    [Fact]
    public async Task RejectedSessionDoesNotRetryOnNetworkWake()
    {
        var calls = 0;
        await using var supervisor = new ConnectionSupervisor(_ =>
        {
            calls++;
            throw new SupabaseSessionExpiredException("existing-user", new Exception("rejected"));
        });
        var states = Observe(supervisor);
        supervisor.Start();
        await ReadUntilAsync(states, ConnectionState.SessionRejected);
        supervisor.RequestReconnect();
        await supervisor.StopAsync();

        Assert.Equal(1, calls);
        Assert.Equal(ConnectionState.Stopped, supervisor.State);
    }

    [Fact]
    public async Task ConcurrentWakeSignalsNeverOverlapBootstrap()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var active = 0;
        var maximumActive = 0;
        await using var supervisor = new ConnectionSupervisor(async token =>
        {
            var count = Interlocked.Increment(ref active);
            maximumActive = Math.Max(maximumActive, count);
            entered.TrySetResult();
            await release.Task.WaitAsync(token);
            Interlocked.Decrement(ref active);
        });
        var states = Observe(supervisor);
        supervisor.Start();
        supervisor.Start();
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await Task.WhenAll(Enumerable.Range(0, 50).Select(_ => Task.Run(supervisor.RequestReconnect)));
        release.SetResult();
        await ReadUntilAsync(states, ConnectionState.Connected);
        await supervisor.StopAsync();

        Assert.Equal(1, maximumActive);
    }

    [Fact]
    public async Task StopCancelsInFlightBootstrap()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var canceled = false;
        await using var supervisor = new ConnectionSupervisor(async token =>
        {
            entered.SetResult();
            try { await Task.Delay(Timeout.InfiniteTimeSpan, token); }
            catch (OperationCanceledException) { canceled = true; throw; }
        });
        supervisor.Start();
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));

        await supervisor.StopAsync();

        Assert.True(canceled);
        Assert.Equal(ConnectionState.Stopped, supervisor.State);
    }

    private static Channel<ConnectionState> Observe(ConnectionSupervisor supervisor)
    {
        var channel = Channel.CreateUnbounded<ConnectionState>();
        supervisor.StateChanged += (state, _) => channel.Writer.TryWrite(state);
        return channel;
    }

    private static async Task ReadUntilAsync(Channel<ConnectionState> channel, ConnectionState expected)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        while (await channel.Reader.ReadAsync(timeout.Token) != expected) { }
    }
}
