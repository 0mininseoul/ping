using Microsoft.UI.Xaml;
using Ping.Windows.App.Bootstrap;

namespace Ping.Windows.App;

public partial class App : Application
{
    private MainWindow? window;
    private AppCoordinator? coordinator;

    public App()
    {
        InitializeComponent();
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

    private void HandleProcessExit(object? sender, EventArgs args)
    {
        DisposeCoordinator();
    }

    private void DisposeCoordinator()
    {
        coordinator?.Dispose();
        coordinator = null;
    }
}
