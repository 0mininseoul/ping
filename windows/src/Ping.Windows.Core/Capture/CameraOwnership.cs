namespace Ping.Windows.Core.Capture;

public enum CameraPurpose { Manual, AutomaticReply }

public sealed class CameraOwnership
{
    private readonly object sync = new();
    private CameraLease? current;
    private int manualWaiters;

    public bool IsBusy { get { lock (sync) return current is not null || manualWaiters != 0; } }

    public CameraLease? TryAcquire(CameraPurpose purpose)
    {
        lock (sync)
        {
            if (current is not null || manualWaiters != 0) return null;
            return current = new CameraLease(this, purpose);
        }
    }

    public async Task<CameraLease?> AcquireManualAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (sync)
        {
            if (current?.Purpose == CameraPurpose.Manual) return null;
            manualWaiters++;
        }
        try
        {
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                CameraLease previous;
                lock (sync)
                {
                    if (current is null) return current = new CameraLease(this, CameraPurpose.Manual);
                    if (current.Purpose == CameraPurpose.Manual) return null;
                    previous = current;
                }
                previous.Interrupt();
                await previous.Released.WaitAsync(cancellationToken).ConfigureAwait(false);
            }
        }
        finally { lock (sync) manualWaiters--; }
    }

    public void InterruptAutomatic()
    {
        CameraLease? automatic;
        lock (sync) automatic = current?.Purpose == CameraPurpose.AutomaticReply ? current : null;
        automatic?.Interrupt();
    }

    internal void Release(CameraLease lease)
    {
        lock (sync)
            if (ReferenceEquals(current, lease)) current = null;
    }
}

public sealed class CameraLease : IDisposable
{
    private readonly CameraOwnership owner;
    private readonly CancellationTokenSource cancellation = new();
    private readonly TaskCompletionSource released = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int disposed;

    internal CameraLease(CameraOwnership owner, CameraPurpose purpose)
    {
        this.owner = owner;
        Purpose = purpose;
        Token = cancellation.Token;
    }

    public CameraPurpose Purpose { get; }
    public CancellationToken Token { get; }
    internal Task Released => released.Task;

    internal void Interrupt()
    {
        try { cancellation.Cancel(); }
        catch (ObjectDisposedException) { }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        Interrupt();
        owner.Release(this);
        released.TrySetResult();
        cancellation.Dispose();
    }
}
