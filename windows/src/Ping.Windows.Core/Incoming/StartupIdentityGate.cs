namespace Ping.Windows.Core.Incoming;

public sealed class StartupIdentityGate
{
    private readonly object sync = new();
    private TaskCompletionSource<string> ready = NewCompletion();

    public Task<string> WaitAsync(CancellationToken token = default)
    {
        lock (sync) return ready.Task.WaitAsync(token);
    }

    public void SetReady(string uid)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uid);
        lock (sync) ready.TrySetResult(uid);
    }

    public void Fail(Exception error)
    {
        lock (sync)
        {
            ready.TrySetException(error);
            _ = ready.Task.Exception;
        }
    }

    public void PrepareRetry()
    {
        lock (sync)
            if (ready.Task.IsFaulted || ready.Task.IsCanceled) ready = NewCompletion();
    }

    private static TaskCompletionSource<string> NewCompletion() => new(TaskCreationOptions.RunContinuationsAsynchronously);
}
