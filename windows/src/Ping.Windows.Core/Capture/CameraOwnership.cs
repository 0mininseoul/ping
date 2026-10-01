namespace Ping.Windows.Core.Capture;

public enum CameraPurpose { Manual, AutomaticReply }

public sealed class CameraOwnership(Func<CaptureDevicePreferences>? preferences = null)
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
            return current = new CameraLease(this, purpose, preferences?.Invoke() ?? new());
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
                    if (current is null) return current = new CameraLease(this, CameraPurpose.Manual, preferences?.Invoke() ?? new());
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

    internal CameraLease(CameraOwnership owner, CameraPurpose purpose, CaptureDevicePreferences devices)
    {
        this.owner = owner;
        Purpose = purpose;
        Devices = devices;
        Token = cancellation.Token;
        CameraSelection = new(Token);
        MicrophoneSelection = new(Token, _ => { });
    }

    public CameraPurpose Purpose { get; }
    public CaptureDevicePreferences Devices { get; }
    public CancellationToken Token { get; }
    public CaptureCameraSelection CameraSelection { get; }
    public CaptureDeviceSelection<CaptureMicrophoneDevice> MicrophoneSelection { get; }
    internal Task Released => released.Task;

    internal void Interrupt()
    {
        try { cancellation.Cancel(); }
        catch (ObjectDisposedException) { }
        catch (AggregateException) { }
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
