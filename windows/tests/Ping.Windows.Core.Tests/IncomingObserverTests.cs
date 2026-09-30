using Ping.Windows.Core.Incoming;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class IncomingObserverTests
{
    [Fact]
    public async Task ConcurrentSignalsCoalesceAndNeverOverlapFetches()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var second = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var sources = new List<IncomingArrivalSource>();
        var active = 0;
        var maximum = 0;
        await using var observer = new IncomingObserver(async (source, token) =>
        {
            maximum = Math.Max(maximum, Interlocked.Increment(ref active));
            sources.Add(source);
            if (sources.Count == 1) { entered.TrySetResult(); await release.Task.WaitAsync(token); }
            else second.TrySetResult();
            Interlocked.Decrement(ref active);
        }, () => TimeSpan.FromHours(1));
        observer.Start();
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        for (var index = 0; index < 100; index++) observer.Signal(IncomingArrivalSource.Live);
        observer.Signal(IncomingArrivalSource.ReconnectCatchUp);
        release.TrySetResult();
        await second.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await observer.StopAsync();
        Assert.Equal(1, maximum);
        Assert.Equal(new[] { IncomingArrivalSource.StartupCatchUp, IncomingArrivalSource.ReconnectCatchUp }, sources);
    }

    [Fact]
    public async Task FailedStartupRemainsCatchUpAndCancellationAwaitsWork()
    {
        var calls = 0;
        var errorReported = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var waiting = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var cancelled = false;
        await using var observer = new IncomingObserver(async (source, token) =>
        {
            Assert.Equal(IncomingArrivalSource.StartupCatchUp, source);
            if (Interlocked.Increment(ref calls) == 1) throw new IOException("fixture");
            waiting.TrySetResult();
            try { await Task.Delay(Timeout.Infinite, token); }
            finally { cancelled = token.IsCancellationRequested; }
        }, () => TimeSpan.FromHours(1), _ => errorReported.TrySetResult());
        observer.Start();
        await errorReported.Task.WaitAsync(TimeSpan.FromSeconds(3));
        observer.Signal(IncomingArrivalSource.Live);
        await waiting.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await observer.DisposeAsync();
        Assert.True(cancelled);
        Assert.False(observer.IsRunning);
    }

    [Fact]
    public async Task PeriodicReconciliationContinuesWithoutRealtimeSignals()
    {
        var sources = new List<IncomingArrivalSource>();
        var reached = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var observer = new IncomingObserver((source, _) =>
        {
            sources.Add(source);
            if (sources.Count == 3) reached.TrySetResult();
            return Task.CompletedTask;
        }, () => TimeSpan.FromMilliseconds(10));
        observer.Start();
        observer.Start();
        await reached.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await observer.StopAsync();
        Assert.Equal(IncomingArrivalSource.StartupCatchUp, sources[0]);
        Assert.All(sources.Skip(1), source => Assert.Equal(IncomingArrivalSource.Live, source));
    }

    [Fact]
    public async Task FailedReconnectBatchKeepsCatchUpSourceForRetry()
    {
        var sources = new List<IncomingArrivalSource>();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var failed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var retried = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var observer = new IncomingObserver((source, _) =>
        {
            sources.Add(source);
            if (sources.Count == 1) started.TrySetResult();
            if (sources.Count == 2) throw new IOException("fixture");
            if (sources.Count == 3) retried.TrySetResult();
            return Task.CompletedTask;
        }, () => TimeSpan.FromHours(1), _ => failed.TrySetResult());
        observer.Start();
        await started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        observer.Signal(IncomingArrivalSource.ReconnectCatchUp);
        await failed.Task.WaitAsync(TimeSpan.FromSeconds(3));
        observer.Signal();
        await retried.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await observer.StopAsync();
        Assert.Equal(new[] { IncomingArrivalSource.StartupCatchUp, IncomingArrivalSource.ReconnectCatchUp, IncomingArrivalSource.ReconnectCatchUp }, sources);
    }

    [Fact]
    public async Task LiveNetworkFailureRecoversAsCatchUpBeforeAnyNewLiveBatch()
    {
        var sources = new List<IncomingArrivalSource>();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var failed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var retried = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var observer = new IncomingObserver((source, _) =>
        {
            sources.Add(source);
            if (sources.Count == 1) started.TrySetResult();
            if (sources.Count == 2) throw new HttpRequestException("offline");
            if (sources.Count == 3) retried.TrySetResult();
            return Task.CompletedTask;
        }, () => TimeSpan.FromHours(1), _ => failed.TrySetResult());
        observer.Start();
        await started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        observer.Signal();
        await failed.Task.WaitAsync(TimeSpan.FromSeconds(3));
        observer.Signal();
        await retried.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await observer.StopAsync();
        Assert.Equal(new[] { IncomingArrivalSource.StartupCatchUp, IncomingArrivalSource.Live, IncomingArrivalSource.ReconnectCatchUp }, sources);
    }
}
