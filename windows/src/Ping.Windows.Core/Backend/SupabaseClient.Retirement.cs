namespace Ping.Windows.Core.Backend;

public sealed partial class SupabaseClient
{
    private readonly CancellationTokenSource requestLifetime = new();
    private volatile bool retiring;
    private volatile bool retired;
    private int disposeState;

    private void ThrowIfRetired() => ObjectDisposedException.ThrowIf(retiring || retired, this);

    public async Task RetireAsync()
    {
        retiring = true;
        await authLock.WaitAsync().ConfigureAwait(false);
        try
        {
            if (retired) return;
            // Preserve an already rotated token before another client opens the account file.
            if (sessionPersistencePending && accounts is not null)
            {
                await sessionStore.SaveAccountsAsync(accounts, CancellationToken.None).ConfigureAwait(false);
                sessionPersistencePending = false;
            }
            retired = true;
            requestLifetime.Cancel();
        }
        catch { retiring = false; throw; }
        finally { authLock.Release(); }
    }
}
