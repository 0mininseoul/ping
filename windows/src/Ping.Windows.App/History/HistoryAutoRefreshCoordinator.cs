namespace Ping.Windows.App.History;

public sealed class HistoryAutoRefreshCoordinator
{
    private readonly TimeSpan interval;
    private readonly Func<CancellationToken, Task> refreshAsync;
    private readonly Func<TimeSpan, CancellationToken, Task> delayAsync;
    private readonly object sync = new();
    private CancellationTokenSource? cancellation;
    private Task? loopTask;
    private int refreshInProgress;

    public HistoryAutoRefreshCoordinator(
        TimeSpan interval,
        Func<CancellationToken, Task> refreshAsync,
        Func<TimeSpan, CancellationToken, Task>? delayAsync = null)
    {
        if (interval <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(interval), interval, "Refresh interval must be positive.");
        }

        this.interval = interval;
        this.refreshAsync = refreshAsync;
        this.delayAsync = delayAsync ?? Task.Delay;
    }

    public bool IsRunning
    {
        get
        {
            lock (sync)
            {
                return loopTask is { IsCompleted: false };
            }
        }
    }

    public void Start()
    {
        lock (sync)
        {
            if (loopTask is { IsCompleted: false })
            {
                return;
            }

            cancellation?.Dispose();
            cancellation = new CancellationTokenSource();
            loopTask = RunAsync(cancellation.Token);
        }
    }

    public async Task StopAsync()
    {
        CancellationTokenSource? source;
        Task? task;
        lock (sync)
        {
            source = cancellation;
            task = loopTask;
            cancellation = null;
            loopTask = null;
        }

        if (source is null)
        {
            return;
        }

        source.Cancel();
        try
        {
            if (task is not null)
            {
                await task.ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            source.Dispose();
        }
    }

    public async Task RefreshOnceAsync(CancellationToken cancellationToken = default)
    {
        if (Interlocked.Exchange(ref refreshInProgress, 1) == 1)
        {
            return;
        }

        try
        {
            await refreshAsync(cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            Interlocked.Exchange(ref refreshInProgress, 0);
        }
    }

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            await delayAsync(interval, cancellationToken).ConfigureAwait(false);
            try
            {
                await RefreshOnceAsync(cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch
            {
            }
        }
    }
}
