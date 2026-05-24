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
        window.Closed += HandleWindowClosed;
        coordinator = new AppCoordinator(window);
        coordinator.Start();
        window.Activate();
    }

    private void HandleWindowClosed(object sender, WindowEventArgs args)
    {
        DisposeCoordinator();
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
