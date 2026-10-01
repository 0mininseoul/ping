namespace Ping.Windows.Core.Capture;

public class CaptureDeviceSelection<T> where T : class
{
    private readonly object sync = new();
    private readonly CancellationToken lifetime;
    private readonly Action<T> validate;
    private Task<T>? selection;

    internal CaptureDeviceSelection(CancellationToken lifetime, Action<T> validate)
        => (this.lifetime, this.validate) = (lifetime, validate);

    public async Task<T> GetAsync(Func<CancellationToken, Task<T>> resolve, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(resolve);
        using var request = CancellationTokenSource.CreateLinkedTokenSource(lifetime, token);
        request.Token.ThrowIfCancellationRequested();
        TaskCompletionSource<T>? first = null;
        Task<T> pending;
        lock (sync)
        {
            if (selection is null)
            {
                first = new(TaskCreationOptions.RunContinuationsAsynchronously);
                selection = first.Task;
            }
            pending = selection;
        }
        if (first is not null) _ = ResolveAsync(resolve, first);
        // Enumeration must finish before the caller can release camera ownership.
        var deviceId = await pending.ConfigureAwait(false);
        request.Token.ThrowIfCancellationRequested();
        return deviceId;
    }

    private async Task ResolveAsync(Func<CancellationToken, Task<T>> resolve, TaskCompletionSource<T> completion)
    {
        try
        {
            var deviceId = await resolve(lifetime);
            lifetime.ThrowIfCancellationRequested();
            ArgumentNullException.ThrowIfNull(deviceId);
            validate(deviceId);
            completion.TrySetResult(deviceId);
        }
        catch (OperationCanceledException error) { completion.TrySetCanceled(error.CancellationToken); }
        catch (Exception error) { completion.TrySetException(error); }
    }
}

