using System.Net;

namespace Ping.Windows.Core.Backend;

public enum ConnectionState { Stopped, Connecting, Connected, Retrying, SessionRejected, ConfigurationRequired }

public sealed class ConnectionSupervisor : IAsyncDisposable
{
    private static readonly int[] RetrySeconds = [1, 2, 5, 10, 30, 60];
    private readonly Func<CancellationToken, Task> connectAsync;
    private readonly Func<TimeSpan, CancellationToken, Task> delayAsync;
    private readonly Func<double> jitter;
    private readonly SemaphoreSlim wake = new(0, 1);
    private readonly object sync = new();
    private CancellationTokenSource? cancellation;
    private Task? loop;
    private volatile ConnectionState state = ConnectionState.Stopped;

    public ConnectionSupervisor(Func<CancellationToken, Task> connectAsync,
        Func<TimeSpan, CancellationToken, Task>? delayAsync = null, Func<double>? jitter = null)
    {
        this.connectAsync = connectAsync;
        this.delayAsync = delayAsync ?? Task.Delay;
        this.jitter = jitter ?? Random.Shared.NextDouble;
    }

    public ConnectionState State => state;
    public event Action<ConnectionState, Exception?>? StateChanged;

    public void Start()
    {
        lock (sync)
        {
            if (loop is { IsCompleted: false }) return;
            cancellation = new CancellationTokenSource();
            loop = Task.Run(() => RunAsync(cancellation.Token));
        }
    }

    public void RequestReconnect()
    {
        if (state is ConnectionState.SessionRejected or ConnectionState.ConfigurationRequired or ConnectionState.Stopped) return;
        Signal();
    }

    public void RetryNow() => Signal();

    private void Signal()
    {
        lock (sync)
        {
            if (cancellation is null || cancellation.IsCancellationRequested) return;
            if (wake.CurrentCount == 0) wake.Release();
        }
    }

    public async Task StopAsync()
    {
        Task? running;
        CancellationTokenSource? source;
        lock (sync)
        {
            source = cancellation;
            running = loop;
            source?.Cancel();
        }
        if (running is not null) await running.ConfigureAwait(false);
        lock (sync)
        {
            if (ReferenceEquals(cancellation, source))
            {
                cancellation = null;
                loop = null;
                source?.Dispose();
            }
        }
    }

    private async Task RunAsync(CancellationToken token)
    {
        var attempt = 0;
        try
        {
            while (!token.IsCancellationRequested)
            {
                while (wake.Wait(0)) { }
                ChangeState(ConnectionState.Connecting);
                try
                {
                    await connectAsync(token).ConfigureAwait(false);
                    attempt = 0;
                    ChangeState(ConnectionState.Connected);
                    await wake.WaitAsync(token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                catch (Exception error)
                {
                    if (error is SupabaseSessionExpiredException or SupabaseSessionReadException)
                    {
                        ChangeState(ConnectionState.SessionRejected, error);
                        await wake.WaitAsync(token).ConfigureAwait(false);
                    }
                    else if (!IsTransient(error))
                    {
                        ChangeState(ConnectionState.ConfigurationRequired, error);
                        await wake.WaitAsync(token).ConfigureAwait(false);
                    }
                    else
                    {
                        ChangeState(ConnectionState.Retrying, error);
                        var seconds = RetrySeconds[Math.Min(attempt++, RetrySeconds.Length - 1)];
                        var duration = TimeSpan.FromSeconds(Math.Min(60, seconds * (0.8 + 0.4 * Math.Clamp(jitter(), 0, 1))));
                        if (error is SupabaseRequestException { RetryAfter: { } serverDelay } && serverDelay > duration)
                            duration = serverDelay;
                        await DelayOrWakeAsync(duration, token).ConfigureAwait(false);
                    }
                }
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        finally { ChangeState(ConnectionState.Stopped); }
    }

    private async Task DelayOrWakeAsync(TimeSpan duration, CancellationToken token)
    {
        using var waitCancellation = CancellationTokenSource.CreateLinkedTokenSource(token);
        var delay = delayAsync(duration, waitCancellation.Token);
        var signal = wake.WaitAsync(waitCancellation.Token);
        var completed = await Task.WhenAny(delay, signal).ConfigureAwait(false);
        await waitCancellation.CancelAsync().ConfigureAwait(false);
        try { await Task.WhenAll(delay, signal).ConfigureAwait(false); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { }
        await completed.ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
    }

    private static bool IsTransient(Exception error) => error switch
    {
        HttpRequestException { StatusCode: null } => true,
        HttpRequestException { StatusCode: HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests } => true,
        HttpRequestException { StatusCode: { } status } => (int)status >= 500,
        OperationCanceledException or TimeoutException or IOException => true,
        _ => false
    };

    private void ChangeState(ConnectionState value, Exception? error = null)
    {
        state = value;
        StateChanged?.Invoke(value, error);
    }

    public async ValueTask DisposeAsync() => await StopAsync().ConfigureAwait(false);
}
