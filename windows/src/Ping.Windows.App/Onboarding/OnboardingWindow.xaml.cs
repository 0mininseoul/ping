using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Ping.Windows.App.Onboarding;

public sealed partial class OnboardingWindow : Window
{
    private readonly PermissionProbe permissionProbe;
    private readonly OnboardingViewModel viewModel;
    private bool didLoad;

    public OnboardingWindow()
        : this(new PermissionProbe())
    {
    }

    internal OnboardingWindow(PermissionProbe permissionProbe)
    {
        this.permissionProbe = permissionProbe;
        viewModel = new OnboardingViewModel();
        InitializeComponent();
        Root.DataContext = viewModel;
    }

    private async void Root_Loaded(object sender, RoutedEventArgs e)
    {
        if (didLoad)
        {
            return;
        }

        didLoad = true;
        await RefreshAsync();
    }

    private async void RetryButton_Click(object sender, RoutedEventArgs e)
    {
        await RefreshAsync();
    }

    private async void PrimaryActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { DataContext: OnboardingRowState { PrimaryAction: { } action } })
        {
            return;
        }

        await ExecuteActionAsync(action);
    }

    private async Task ExecuteActionAsync(OnboardingAction action)
    {
        switch (action.Kind)
        {
            case OnboardingActionKind.Settings when !string.IsNullOrWhiteSpace(action.Uri):
                _ = await SettingsLauncher.LaunchAsync(action.Uri);
                break;
            case OnboardingActionKind.OpenFolder:
                _ = await SettingsLauncher.LaunchFolderAsync(PermissionProbe.DefaultSupabaseDirectoryPath());
                break;
            case OnboardingActionKind.Retry:
            case OnboardingActionKind.Configure:
            case OnboardingActionKind.Relaunch:
            case OnboardingActionKind.None:
            default:
                await RefreshAsync();
                break;
        }
    }

    private async Task RefreshAsync()
    {
        var state = await permissionProbe.ProbeAsync();
        viewModel.Apply(state);
    }
}
