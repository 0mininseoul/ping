using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
using Ping.Windows.App.Bootstrap;
using Ping.Windows.App.Notifications;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Updates;

namespace Ping.Windows.App;

public partial class App : Application
{
    private readonly DispatcherQueue dispatcherQueue;
    private readonly Queue<AppActivationArguments> pendingActivationArguments = new();
    private MainWindow? window;
    private AppCoordinator? coordinator;
    private readonly SemaphoreSlim accountTransition = new(1, 1);
    private SupabaseClient? pendingAccountCreation;
    internal async Task ApplyPreparedUpdateAsync(PreparedWindowsUpdate update)
    {
        await accountTransition.WaitAsync();
        try
        {
            if (coordinator is null || window is null) throw new InvalidOperationException("Ping is not ready.");
            try
            {
                await coordinator.ShutdownForAccountChangeAsync();
                coordinator = null;
                WindowsUpdateController.StartInstaller(update);
                window.CloseForQuit();
                Exit();
            }
            catch
            {
                if (coordinator is null || coordinator.IsDisposed)
                {
                    window.DetachMessenger();
                    coordinator = new AppCoordinator(window); coordinator.Start(); coordinator.OpenSettingsWindow(SettingsSection.Info);
                    coordinator.ReportUpdateFailure();
                }
                throw;
            }
        }
        finally { accountTransition.Release(); }
    }

    internal Task<IReadOnlyList<StoredAccountSummary>> GetAccountsAsync(CancellationToken token) =>
        coordinator?.GetAccountsAsync(token) ?? throw new InvalidOperationException("Account transition is in progress.");

    internal async Task ChangeAccountAsync(AccountChange change, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        await accountTransition.WaitAsync(token);
        try
        {
            if (coordinator is null || window is null) throw new InvalidOperationException("Ping is not ready.");
            try { await coordinator.ShutdownForAccountChangeAsync(); }
            catch
            {
                if (coordinator.IsDisposed)
                {
                    window.DetachMessenger();
                    coordinator = new AppCoordinator(window);
                    coordinator.Start(); coordinator.OpenSettingsWindow(); coordinator.ReportAccountTransitionFailure();
                }
                throw;
            }
            coordinator = null;
            var retainedCreation = pendingAccountCreation;
            var client = change.Kind == AccountChangeKind.Create && pendingAccountCreation is not null
                ? pendingAccountCreation : new SupabaseClient();
            pendingAccountCreation = null;
            if (!ReferenceEquals(client, retainedCreation)) retainedCreation?.Dispose();
            var failed = false;
            try
            {
                switch (change.Kind)
                {
                    case AccountChangeKind.Create: await client.CreateAccountAsync(token); break;
                    case AccountChangeKind.Switch: await client.SwitchAccountAsync(change.UserId!, token); break;
                    case AccountChangeKind.Remove: await client.RemoveAccountAsync(change.UserId!, token); break;
                    default: throw new ArgumentOutOfRangeException(nameof(change));
                }
            }
            catch
            {
                failed = true;
                if (change.Kind == AccountChangeKind.Create) pendingAccountCreation = client;
                throw;
            }
            finally
            {
                if (!ReferenceEquals(client, pendingAccountCreation)) client.Dispose();
                coordinator = new AppCoordinator(window);
                coordinator.Start();
                coordinator.OpenSettingsWindow();
                if (failed) coordinator.ReportAccountTransitionFailure();
                DrainPendingActivationArguments();
            }
        }
        finally { accountTransition.Release(); }
    }

    public App()
    {
        InitializeComponent();
        dispatcherQueue = DispatcherQueue.GetForCurrentThread();
        Program.Activated += HandleRedirectedActivation;
        foreach (var activation in Program.TakePendingActivations())
        {
            HandleRedirectedActivation(this, activation);
        }

        AppDomain.CurrentDomain.ProcessExit += HandleProcessExit;
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
#if PING_UI_SMOKE
        if (Diagnostics.AccountKeyPreview.OutputDirectory is not null)
        {
            _ = Diagnostics.AccountKeyPreview.RunAsync(this);
            return;
        }
        if (Diagnostics.UiSmokeRunner.OutputDirectory is not null)
        {
            _ = Diagnostics.UiSmokeRunner.RunAsync(this);
            return;
        }
#endif
        window = new MainWindow();
        window.InitializeTrayWindowBehavior();
        coordinator = new AppCoordinator(window);
        coordinator.Start(allowBackgroundStartup: true);
        coordinator.HandleInitialNotificationActivation();
        DrainPendingActivationArguments();
    }

    private void HandleRedirectedActivation(object? sender, AppActivationArguments args)
    {
        dispatcherQueue.TryEnqueue(() => HandleActivationArguments(args));
    }

    private void HandleActivationArguments(AppActivationArguments args)
    {
        if (coordinator is null || window is null)
        {
            pendingActivationArguments.Enqueue(args);
            return;
        }

        if (args.Kind == ExtendedActivationKind.AppNotification
            && args.Data is AppNotificationActivatedEventArgs notificationArgs)
        {
            coordinator.HandleNotificationActivation(NotificationActivationArguments.From(notificationArgs));
            return;
        }

        if (args.Kind == ExtendedActivationKind.StartupTask) return;
        coordinator.ShowMessenger();
    }

    private void DrainPendingActivationArguments()
    {
        while (pendingActivationArguments.Count > 0)
        {
            HandleActivationArguments(pendingActivationArguments.Dequeue());
        }
    }

    private void HandleProcessExit(object? sender, EventArgs args)
    {
        DisposeCoordinator();
    }

    private void DisposeCoordinator()
    {
        Program.Activated -= HandleRedirectedActivation;
        coordinator?.Dispose();
        pendingAccountCreation?.Dispose();
        coordinator = null;
    }
}
