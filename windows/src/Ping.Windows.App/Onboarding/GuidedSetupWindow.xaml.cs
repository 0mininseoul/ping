using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Ping.Windows.App.Onboarding;

public sealed partial class GuidedSetupWindow : Window
{
    private readonly GuidedSetupViewModel model;
    private readonly Action complete;
    private readonly Func<CancellationToken, Task<OnboardingEnvironmentState>> probe;
    private readonly CancellationTokenSource lifetime = new();
    private bool closed, checking;
    private GuidedSetupStep? displayedStep;

    internal GuidedSetupWindow(GuidedSetupViewModel model, Action complete,
        Func<CancellationToken, Task<OnboardingEnvironmentState>> probe)
    {
        this.model = model; this.complete = complete; this.probe = probe;
        InitializeComponent();
        UI.PingAppearance.Register(this); UI.WindowCaptureExclusion.Apply(this);
        Root.DataContext = model;
        model.PropertyChanged += ModelChanged;
        Root.Loaded += (_, _) => UpdatePage();
        Closed += (_, _) => { closed = true; model.PropertyChanged -= ModelChanged; model.Dispose(); lifetime.Cancel(); lifetime.Dispose(); };
        UI.SettingsWindowGeometry.Fit(this, 480, 600);
        UpdatePage();
    }
    private void ModelChanged(object? sender, PropertyChangedEventArgs args) { if (!closed) UpdatePage(); }
    private void UpdatePage()
    {
        foreach (var (element, step) in new (FrameworkElement, GuidedSetupStep)[]
        {
            (WelcomePage, GuidedSetupStep.Welcome), (PermissionsPage, GuidedSetupStep.Permissions), (NicknamePage, GuidedSetupStep.Nickname),
            (ConnectionPage, GuidedSetupStep.ConnectionChoice), (CreatePage, GuidedSetupStep.CreateRoom), (JoinPage, GuidedSetupStep.JoinRoom), (DonePage, GuidedSetupStep.Done)
        }) element.Visibility = model.Step == step ? Visibility.Visible : Visibility.Collapsed;
        BackButton.Visibility = model.Step is GuidedSetupStep.Welcome or GuidedSetupStep.Done ? Visibility.Collapsed : Visibility.Visible;
        NextButton.Visibility = model.Step == GuidedSetupStep.ConnectionChoice ? Visibility.Collapsed : Visibility.Visible;
        PermissionsHint.Visibility = model.Step == GuidedSetupStep.Permissions ? Visibility.Visible : Visibility.Collapsed;
        ErrorRow.Visibility = model.IsBusy || !string.IsNullOrEmpty(model.Error) ? Visibility.Visible : Visibility.Collapsed;
        if (displayedStep == model.Step) return;
        displayedStep = model.Step;
        Root.DispatcherQueue.TryEnqueue(() =>
        {
            if (closed) return;
            var input = model.Step switch { GuidedSetupStep.Nickname => NicknameInput, GuidedSetupStep.CreateRoom => RoomNameInput,
                GuidedSetupStep.JoinRoom => RoomSearchInput, _ => null };
            input?.Focus(FocusState.Programmatic);
        });
    }
    private async void Next_Click(object sender, RoutedEventArgs args)
    {
        if (checking || !model.CanContinue) return;
        if (model.Step == GuidedSetupStep.Done) { complete(); Close(); return; }
        await model.NextAsync();
    }
    private void Back_Click(object sender, RoutedEventArgs args) { if (!checking) model.Back(); }
    private void CreateChoice_Click(object sender, RoutedEventArgs args) => model.ChooseCreateRoom();
    private void JoinChoice_Click(object sender, RoutedEventArgs args) => model.ChooseJoinRoom();
    private void Later_Click(object sender, RoutedEventArgs args) => model.StartLater();
    private async void SearchRooms_Click(object sender, RoutedEventArgs args) => await model.SearchAsync();
    private async void Input_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs args)
    {
        if (args.Key != global::Windows.System.VirtualKey.Enter || checking || !model.CanContinue) return;
        args.Handled = true; await model.NextAsync();
    }
    private async void Search_KeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs args)
    {
        if (args.Key != global::Windows.System.VirtualKey.Enter || !model.CanEdit) return;
        args.Handled = true; await model.SearchAsync();
    }
    private async void PermissionSettings_Click(object sender, RoutedEventArgs args)
    {
        if (sender is Button { Tag: string uri }) await SettingsLauncher.LaunchAsync(uri);
    }
    private async void CheckPermissions_Click(object sender, RoutedEventArgs args)
    {
        if (checking) return;
        checking = true; CheckPermissionsButton.IsEnabled = false; NextButton.IsEnabled = false; BackButton.IsEnabled = false;
        var token = lifetime.Token;
        try
        {
            var state = await probe(token);
            if (closed) return;
            CameraStatus.Text = StatusText(state.Camera); MicrophoneStatus.Text = StatusText(state.Microphone);
            NotificationsStatus.Text = StatusText(state.Notifications); ScreenStatus.Text = StatusText(state.ScreenCapture);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception) { if (!closed) CameraStatus.Text = "상태를 확인하지 못했어요. 다시 시도해 주세요."; }
        finally
        {
            checking = false;
            if (!closed) { CheckPermissionsButton.IsEnabled = true; NextButton.ClearValue(Control.IsEnabledProperty); BackButton.ClearValue(Control.IsEnabledProperty);
                NextButton.SetBinding(Control.IsEnabledProperty, new Microsoft.UI.Xaml.Data.Binding { Path = new("CanContinue") });
                BackButton.SetBinding(Control.IsEnabledProperty, new Microsoft.UI.Xaml.Data.Binding { Path = new("CanGoBack") }); }
        }
    }
    private static string StatusText(OnboardingProbeState state) => state.Status switch
    {
        OnboardingProbeStatus.Available => "사용할 수 있어요", OnboardingProbeStatus.Blocked => "기기 또는 권한을 확인해 주세요",
        OnboardingProbeStatus.Unsupported => "이 Windows에서는 지원되지 않아요", _ => "아직 확인하지 않았어요"
    };
}
