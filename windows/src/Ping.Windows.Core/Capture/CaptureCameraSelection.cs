namespace Ping.Windows.Core.Capture;

public sealed class CaptureCameraSelection
{
    private readonly object sync = new();
    private readonly CancellationToken lifetime;
    private Task<string>? selection;

    internal CaptureCameraSelection(CancellationToken lifetime) => this.lifetime = lifetime;

    public async Task<string> GetAsync(Func<CancellationToken, Task<string>> resolve, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(resolve);
        using var request = CancellationTokenSource.CreateLinkedTokenSource(lifetime, token);
        request.Token.ThrowIfCancellationRequested();
        TaskCompletionSource<string>? first = null;
        Task<string> pending;
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

    private async Task ResolveAsync(Func<CancellationToken, Task<string>> resolve, TaskCompletionSource<string> completion)
    {
        try
        {
            var deviceId = await resolve(lifetime);
            lifetime.ThrowIfCancellationRequested();
            if (string.IsNullOrWhiteSpace(deviceId) || deviceId.Contains('\0'))
                throw new InvalidOperationException("사용할 카메라를 찾을 수 없습니다.");
            completion.TrySetResult(deviceId);
        }
        catch (OperationCanceledException error) { completion.TrySetCanceled(error.CancellationToken); }
        catch (Exception error) { completion.TrySetException(error); }
    }
}
