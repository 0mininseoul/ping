using Ping.Windows.Core.Backend;

namespace Ping.Windows.Core.Incoming;

public sealed class IncomingObserver : IAsyncDisposable
{
    private readonly Func<IncomingArrivalSource, CancellationToken, Task> reconcile;
    private readonly Func<TimeSpan> interval;
    private readonly Action<Exception>? onError;
    private readonly object sync = new();
    private readonly SemaphoreSlim wake = new(0, 1);
    private CancellationTokenSource? cancellation;
    private Task? loop;
    private IncomingArrivalSource? pending;
    private bool disposed;

    public IncomingObserver(Func<IncomingArrivalSource, CancellationToken, Task> reconcile, Func<TimeSpan> interval,
        Action<Exception>? onError = null)
    {
        this.reconcile = reconcile;
        this.interval = interval;
        this.onError = onError;
    }

    public bool IsRunning { get { lock (sync) return loop is { IsCompleted: false }; } }

    public void Start()
    {
        lock (sync)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (loop is { IsCompleted: false }) return;
            cancellation?.Dispose();
            cancellation = new();
            pending = null;
            while (wake.Wait(0)) { }
            var token = cancellation.Token;
            loop = Task.Run(() => RunAsync(token));
        }
    }

    public void Signal(IncomingArrivalSource source = IncomingArrivalSource.Live)
    {
        if (source is IncomingArrivalSource.NotificationClick or IncomingArrivalSource.HistoryReplay) throw new ArgumentOutOfRangeException(nameof(source));
        lock (sync)
        {
            if (disposed || cancellation is null || cancellation.IsCancellationRequested) return;
            if (pending is null || Priority(source) > Priority(pending.Value)) pending = source;
            if (wake.CurrentCount == 0) wake.Release();
        }
    }

    private async Task RunAsync(CancellationToken token)
    {
        var startup = true;
        try
        {
            while (true)
            {
                token.ThrowIfCancellationRequested();
                IncomingArrivalSource source;
                lock (sync)
                {
                    source = startup ? IncomingArrivalSource.StartupCatchUp : pending ?? IncomingArrivalSource.Live;
                    pending = null;
                    while (wake.Wait(0)) { }
                }
                try
                {
                    await reconcile(source, token).ConfigureAwait(false);
                    startup = false;
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                catch (Exception error)
                {
                    onError?.Invoke(error);
                    if (error is SupabaseSessionExpiredException or SupabaseSessionReadException) return;
                    lock (sync)
                    {
                        var retrySource = source == IncomingArrivalSource.Live && error is HttpRequestException or IOException or TimeoutException or OperationCanceledException
                            ? IncomingArrivalSource.ReconnectCatchUp : source;
                        if (pending is null || Priority(retrySource) > Priority(pending.Value)) pending = retrySource;
                    }
                }
                await WaitAsync(token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
    }

    private async Task WaitAsync(CancellationToken token)
    {
        using var wait = CancellationTokenSource.CreateLinkedTokenSource(token);
        var duration = interval();
        if (duration <= TimeSpan.Zero) duration = TimeSpan.FromSeconds(1);
        var delay = Task.Delay(duration, wait.Token);
        var signal = wake.WaitAsync(wait.Token);
        var completed = await Task.WhenAny(delay, signal).ConfigureAwait(false);
        await wait.CancelAsync().ConfigureAwait(false);
        try { await Task.WhenAll(delay, signal).ConfigureAwait(false); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { }
        await completed.ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
    }

    private static int Priority(IncomingArrivalSource source) => source switch
    { IncomingArrivalSource.StartupCatchUp => 3, IncomingArrivalSource.ReconnectCatchUp => 2, _ => 1 };

    public async Task StopAsync()
    {
        Task? running;
        CancellationTokenSource? source;
        lock (sync) { source = cancellation; running = loop; source?.Cancel(); }
        if (running is not null) await running.ConfigureAwait(false);
        lock (sync)
        {
            if (!ReferenceEquals(cancellation, source)) return;
            source?.Dispose();
            cancellation = null;
            loop = null;
            pending = null;
        }
    }

    public async ValueTask DisposeAsync()
    {
        lock (sync) disposed = true;
        await StopAsync().ConfigureAwait(false);
    }
}
