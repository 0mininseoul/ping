namespace Ping.Windows.Core.Backend;

public sealed partial class SupabaseClient
{
    private SupabaseAccountsState? accounts;
    private SupabaseSession? pendingCreatedAccount;

    private async Task LoadAccountsLockedAsync(CancellationToken token)
    {
        if (accounts is not null) return;
        accounts = await sessionStore.LoadAccountsAsync(token).ConfigureAwait(false);
        session = accounts.ActiveSession;
    }
    private async Task CommitAccountsLockedAsync(SupabaseAccountsState next, CancellationToken token)
    {
        await sessionStore.SaveAccountsAsync(next, token).ConfigureAwait(false);
        accounts = next; session = next.ActiveSession; sessionPersistencePending = false;
    }
    public async Task<IReadOnlyList<StoredAccountSummary>> GetAccountsAsync(CancellationToken cancellationToken = default)
    {
        await authLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAccountsLockedAsync(cancellationToken).ConfigureAwait(false);
            return accounts!.Accounts.Select(row => new StoredAccountSummary(row.Session.UserId, row.Nickname, row.AddedAt,
                row.Session.UserId == accounts.ActiveUserId)).ToArray();
        }
        finally { authLock.Release(); }
    }
    public async Task<string> CreateAccountAsync(CancellationToken cancellationToken = default)
    {
        await authLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAccountsLockedAsync(cancellationToken).ConfigureAwait(false);
            pendingCreatedAccount ??= await SignInAnonymouslyAsync(cancellationToken).ConfigureAwait(false);
            var created = pendingCreatedAccount;
            await CommitAccountsLockedAsync(accounts!.Upsert(created, activate: true), cancellationToken).ConfigureAwait(false);
            pendingCreatedAccount = null;
            return created.UserId;
        }
        finally { authLock.Release(); }
    }
    public async Task SwitchAccountAsync(string userId, CancellationToken cancellationToken = default)
    {
        await authLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAccountsLockedAsync(cancellationToken).ConfigureAwait(false);
            await CommitAccountsLockedAsync(accounts!.Switch(userId), cancellationToken).ConfigureAwait(false);
        }
        finally { authLock.Release(); }
    }
    public async Task RemoveAccountAsync(string userId, CancellationToken cancellationToken = default)
    {
        await authLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAccountsLockedAsync(cancellationToken).ConfigureAwait(false);
            await CommitAccountsLockedAsync(accounts!.Remove(userId), cancellationToken).ConfigureAwait(false);
        }
        finally { authLock.Release(); }
    }
    public async Task UpdateAccountNicknameAsync(string nickname, CancellationToken cancellationToken = default)
    {
        await authLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await LoadAccountsLockedAsync(cancellationToken).ConfigureAwait(false);
            if (accounts!.ActiveUserId is null) throw new SupabaseAccountRequiredException();
            await CommitAccountsLockedAsync(accounts.Rename(nickname.Trim()), cancellationToken).ConfigureAwait(false);
        }
        finally { authLock.Release(); }
    }
}
