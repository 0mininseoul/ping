using Ping.Windows.Core.Backend;

namespace Ping.Windows.Core.Realtime;

public enum RealtimeConnectionState { Stopped, Connecting, Connected, FallbackPolling, RecoveryRequired, ConfigurationRequired }

public sealed class RealtimeSupervisor : IAsyncDisposable
{
    private static readonly int[] RetrySeconds = [1, 2, 5, 10, 30, 60];
    private readonly Func<CancellationToken, Task<RealtimeCredentials>> credentials;
    private readonly Func<RealtimeChange, CancellationToken, Task> onChange;
    private readonly Func<IRealtimeTransport> transportFactory;
    private readonly Func<TimeSpan, CancellationToken, Task> delayAsync;
    private readonly Func<double> jitter;
    private readonly RealtimeConnectionOptions? options;
    private readonly SemaphoreSlim lifecycle = new(1, 1);
    private CancellationTokenSource? cancellation;
    private Task? loop;
    private string? userUid;
    private string[] roomIds = [];
    private bool disposed;
    private volatile RealtimeConnectionState state = RealtimeConnectionState.Stopped;

    public RealtimeSupervisor(Func<CancellationToken, Task<RealtimeCredentials>> credentials,
        Func<RealtimeChange, CancellationToken, Task> onChange, Func<IRealtimeTransport>? transportFactory = null,
        Func<TimeSpan, CancellationToken, Task>? delayAsync = null, Func<double>? jitter = null,
        RealtimeConnectionOptions? options = null)
    {
        this.credentials = credentials;
        this.onChange = onChange;
        this.transportFactory = transportFactory ?? (() => new RealtimeWebSocketTransport());
        this.delayAsync = delayAsync ?? Task.Delay;
        this.jitter = jitter ?? Random.Shared.NextDouble;
        this.options = options;
    }

    public RealtimeConnectionState State => state;
    public event Action<RealtimeConnectionState>? StateChanged;
    public event Action<Exception>? RecoveryRequired;

    public async Task UpdateAsync(string uid, IReadOnlyCollection<string> rooms, bool forceReconnect = false,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uid);
        var snapshot = rooms.Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray();
        await lifecycle.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (!forceReconnect && userUid == uid && roomIds.SequenceEqual(snapshot) && loop is not null) return;
            await StopCoreAsync().ConfigureAwait(false);
            userUid = uid;
            roomIds = snapshot;
            cancellation = new CancellationTokenSource();
            var token = cancellation.Token;
            loop = Task.Run(() => RunAsync(uid, snapshot, token));
        }
        finally { lifecycle.Release(); }
    }

    private async Task RunAsync(string uid, string[] rooms, CancellationToken token)
    {
        var attempt = 0;
        try
        {
            while (true)
            {
                token.ThrowIfCancellationRequested();
                ChangeState(RealtimeConnectionState.Connecting);
                try
                {
                    var current = await credentials(token).ConfigureAwait(false);
                    if (current.UserUid != uid) throw new RealtimeIdentityChangedException();
                    await using var transport = transportFactory();
                    await new RealtimeConnection(transport, options).RunAsync(RealtimeProtocol.Channels(uid, rooms), current, credentials,
                        () => { attempt = 0; ChangeState(RealtimeConnectionState.Connected); }, onChange, token).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                catch (Exception error)
                {
                    if (error is SupabaseSessionExpiredException or SupabaseSessionReadException or RealtimeIdentityChangedException)
                    {
                        ChangeState(RealtimeConnectionState.RecoveryRequired);
                        RecoveryRequired?.Invoke(error);
                        return;
                    }
                    if (error is FileNotFoundException or DirectoryNotFoundException or ArgumentException)
                    {
                        ChangeState(RealtimeConnectionState.ConfigurationRequired);
                        RecoveryRequired?.Invoke(error);
                        return;
                    }
                    ChangeState(RealtimeConnectionState.FallbackPolling);
                    var seconds = RetrySeconds[Math.Min(attempt++, RetrySeconds.Length - 1)];
                    var duration = TimeSpan.FromSeconds(Math.Min(60, seconds * (1 + 0.2 * Math.Clamp(jitter(), 0, 1))));
                    if (error is SupabaseRequestException { RetryAfter: { } serverDelay } && serverDelay > duration) duration = serverDelay;
                    await delayAsync(duration, token).ConfigureAwait(false);
                }
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        finally { if (token.IsCancellationRequested) ChangeState(RealtimeConnectionState.Stopped); }
    }

    public async Task StopAsync()
    {
        await lifecycle.WaitAsync().ConfigureAwait(false);
        try { await StopCoreAsync().ConfigureAwait(false); }
        finally { lifecycle.Release(); }
    }

    private async Task StopCoreAsync()
    {
        cancellation?.Cancel();
        if (loop is not null) await loop.ConfigureAwait(false);
        cancellation?.Dispose();
        cancellation = null;
        loop = null;
        userUid = null;
        roomIds = [];
        ChangeState(RealtimeConnectionState.Stopped);
    }

    private void ChangeState(RealtimeConnectionState value)
    {
        state = value;
        StateChanged?.Invoke(value);
    }

    public async ValueTask DisposeAsync()
    {
        await lifecycle.WaitAsync().ConfigureAwait(false);
        try
        {
            if (disposed) return;
            disposed = true;
            await StopCoreAsync().ConfigureAwait(false);
        }
        finally { lifecycle.Release(); }
    }
}
