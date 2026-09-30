namespace Ping.Windows.Core.Capture;

public sealed class CaptureActivityState
{
    private readonly object sync = new();
    private bool displayAwake = true;
    private bool suspended;
    private bool locked;
    private long generation;

    public CaptureActivityState(bool initiallyBlocked = false) => displayAwake = !initiallyBlocked;

    public event Action? Interrupted;
    public bool IsBlocked { get { lock (sync) return !displayAwake || suspended || locked; } }
    public long Generation { get { lock (sync) return generation; } }
    public bool WasInterruptedSince(long previous) { lock (sync) return generation != previous; }

    public void SetDisplayAwake(bool awake) => Update(() => displayAwake = awake);
    public void SetSuspended(bool value) => Update(() => suspended = value);
    public void SetLocked(bool value) => Update(() => locked = value);

    private void Update(Action update)
    {
        bool interrupt;
        lock (sync)
        {
            var wasBlocked = !displayAwake || suspended || locked;
            update();
            interrupt = !wasBlocked && (!displayAwake || suspended || locked);
            if (interrupt) generation++;
        }
        if (interrupt) Interrupted?.Invoke();
    }
}
