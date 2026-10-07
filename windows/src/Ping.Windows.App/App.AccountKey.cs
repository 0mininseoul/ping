using Ping.Windows.App.Bootstrap;
using Ping.Windows.Core.Backend;

namespace Ping.Windows.App;

public partial class App
{
    private ConnectedPingAccount? pendingConnectedAccount;
    internal bool HasPendingConnectedAccount => pendingConnectedAccount is not null;

    internal async Task<ConnectedPingAccount> AuthenticateAccountKeyAsync(string nickname, string key, CancellationToken token)
    {
        await accountTransition.WaitAsync(token);
        try
        {
            if (pendingConnectedAccount is not null)
                throw new AccountKeyException("이미 연결한 계정의 저장이 남아 있어요. 설정에서 ‘연결 저장 재시도’를 눌러 주세요.");
            using var client = new SupabaseClient();
            return await client.AuthenticateAccountKeyAsync(nickname, key, token);
        }
        finally { accountTransition.Release(); }
    }

    internal async Task<bool> GetAccountKeyStatusAsync(AppCoordinator expected, CancellationToken token)
    {
        if (!ReferenceEquals(coordinator, expected)) throw new AccountKeyException("사용 중인 계정이 바뀌었어요. 설정을 다시 열어 주세요.");
        return await expected.GetAccountKeyStatusAsync(token);
    }

    internal async Task SetAccountKeyAsync(AppCoordinator expected, string key, CancellationToken token)
    {
        await accountTransition.WaitAsync(token);
        try
        {
            if (!ReferenceEquals(coordinator, expected)) throw new AccountKeyException("사용 중인 계정이 바뀌었어요. 설정을 다시 열어 주세요.");
            await expected.SetAccountKeyAsync(key, token);
        }
        finally { accountTransition.Release(); }
    }

    internal async Task CompleteAccountConnectionAsync(ConnectedPingAccount? authenticated = null)
    {
        // Authentication finishes before any window is closed. Persistence is not canceled by closing the old Settings window.
        await accountTransition.WaitAsync();
        try
        {
            if (coordinator is null || window is null) throw new InvalidOperationException("Ping is not ready.");
            if (pendingConnectedAccount is not null && authenticated is not null &&
                !ReferenceEquals(pendingConnectedAccount, authenticated))
                throw new AccountKeyException("이전에 연결한 계정의 저장을 먼저 재시도해 주세요.");
            pendingConnectedAccount ??= authenticated ?? throw new InvalidOperationException("No account connection is pending.");
            var failed = true;
            try
            {
                await coordinator.ShutdownForAccountChangeAsync();
                coordinator = null;
                using var client = new SupabaseClient();
                await client.ImportConnectedAccountAsync(pendingConnectedAccount, CancellationToken.None);
                pendingConnectedAccount = null;
                pendingAccountCreation?.Dispose();
                pendingAccountCreation = null;
                failed = false;
            }
            finally
            {
                if (coordinator is null || coordinator.IsDisposed)
                {
                    window.DetachMessenger();
                    coordinator = new AppCoordinator(window);
                    coordinator.Start();
                }
                if (failed) { coordinator.OpenSettingsWindow(); coordinator.ReportAccountKeyImportFailure(); }
                else coordinator.ShowMessenger();
                DrainPendingActivationArguments();
            }
        }
        finally { accountTransition.Release(); }
    }
}
