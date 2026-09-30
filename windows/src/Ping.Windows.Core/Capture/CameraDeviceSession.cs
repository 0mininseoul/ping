namespace Ping.Windows.Core.Capture;

public sealed class CameraDeviceSession<TDevice> : IAsyncDisposable where TDevice : class
{
    private readonly object sync = new();
    private readonly SemaphoreSlim operations = new(1, 1);
    private readonly CancellationTokenSource lifetime;
    private readonly CancellationToken lifetimeToken;
    private readonly Func<CancellationToken, Task<TDevice>> initialize;
    private readonly Func<TDevice, ValueTask> disposeDevice;
    private TDevice? device;
    private Task? closeTask;

    public CameraDeviceSession(CameraLease lease, Func<CancellationToken, Task<TDevice>> initialize,
        Func<TDevice, ValueTask> disposeDevice)
    {
        lease.Token.ThrowIfCancellationRequested();
        this.initialize = initialize;
        this.disposeDevice = disposeDevice;
        lifetime = CancellationTokenSource.CreateLinkedTokenSource(lease.Token);
        lifetimeToken = lifetime.Token;
    }

    public async Task<TResult> UseAsync<TResult>(Func<TDevice, CancellationToken, Task<TResult>> operation,
        CancellationToken cancellationToken = default)
    {
        lifetimeToken.ThrowIfCancellationRequested();
        using var request = CancellationTokenSource.CreateLinkedTokenSource(lifetimeToken, cancellationToken);
        var token = request.Token;
        await operations.WaitAsync(token);
        try
        {
            token.ThrowIfCancellationRequested();
            // Preview callbacks need the caller's UI context; the session never releases a device mid-operation.
            device ??= await initialize(token);
            token.ThrowIfCancellationRequested();
            return await operation(device, token);
        }
        finally { operations.Release(); }
    }

    public ValueTask DisposeAsync()
    {
        lock (sync)
        {
            if (closeTask is not null) return new(closeTask);
            var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            closeTask = completion.Task;
            _ = CloseAsync(completion);
            return new(closeTask);
        }
    }

    private async Task CloseAsync(TaskCompletionSource completion)
    {
        try
        {
            try { lifetime.Cancel(); }
            catch (AggregateException) { }
            await operations.WaitAsync();
            try
            {
                if (device is { } initialized) await disposeDevice(initialized);
                device = null;
            }
            finally { operations.Release(); }
            completion.TrySetResult();
        }
        catch (Exception error) { completion.TrySetException(error); }
        finally { lifetime.Dispose(); }
    }
}
