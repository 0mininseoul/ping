using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
using Ping.Windows.App.Bootstrap;
using Ping.Windows.App.Notifications;

namespace Ping.Windows.App;

public partial class App : Application
{
    private readonly DispatcherQueue dispatcherQueue;
    private MainWindow? window;
    private AppCoordinator? coordinator;

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
        window = new MainWindow();
        window.InitializeTrayWindowBehavior();
        coordinator = new AppCoordinator(window);
        coordinator.Start();
        coordinator.HandleInitialNotificationActivation();
    }

    private void HandleRedirectedActivation(object? sender, AppActivationArguments args)
    {
        dispatcherQueue.TryEnqueue(() => HandleActivationArguments(args));
    }

    private void HandleActivationArguments(AppActivationArguments args)
    {
        if (args.Kind == ExtendedActivationKind.AppNotification
            && args.Data is AppNotificationActivatedEventArgs notificationArgs)
        {
            coordinator?.HandleNotificationActivation(NotificationActivationArguments.From(notificationArgs));
            return;
        }

        window?.ShowShell();
    }

    private void HandleProcessExit(object? sender, EventArgs args)
    {
        DisposeCoordinator();
    }

    private void DisposeCoordinator()
    {
        Program.Activated -= HandleRedirectedActivation;
        coordinator?.Dispose();
        coordinator = null;
    }
}
