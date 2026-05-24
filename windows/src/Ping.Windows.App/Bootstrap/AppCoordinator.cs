using Microsoft.UI.Xaml;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Tray;

namespace Ping.Windows.App.Bootstrap;

public sealed class AppCoordinator : IDisposable
{
    private readonly MainWindow mainWindow;
    private readonly HotkeyPreferencesStore preferencesStore;
    private readonly GlobalHotkeyManager hotkeys;
    private readonly TrayIconController tray;
    private bool disposed;

    public AppCoordinator(MainWindow mainWindow)
        : this(
            mainWindow,
            new HotkeyPreferencesStore(),
            new GlobalHotkeyManager(),
            null)
    {
    }

    internal AppCoordinator(
        MainWindow mainWindow,
        HotkeyPreferencesStore preferencesStore,
        GlobalHotkeyManager hotkeys,
        TrayIconController? tray)
    {
        this.mainWindow = mainWindow;
        this.preferencesStore = preferencesStore;
        this.hotkeys = hotkeys;
        this.tray = tray ?? new TrayIconController(ExecuteTrayCommand);
    }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        hotkeys.HotkeyPressed += HandleHotkeyPressed;
        var registrations = RegisterSavedHotkeys();
        tray.AddOrUpdateIcon();
        ShowHistory("Ping is running. Capture commands are wired and waiting for the capture windows.");
        ShowRegistrationState(registrations);
    }

    public void Execute(HotkeyCommand command)
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        switch (command)
        {
            case HotkeyCommand.FacePing:
                ShowBlockedState(
                    "Face Ping",
                    "Alt+P reached Ping. Face-only capture arrives in the next implementation task.",
                    "Capture window not implemented yet.");
                break;
            case HotkeyCommand.ScreenFacePing:
                ShowBlockedState(
                    "Screen+Face Ping",
                    "Alt+L reached Ping. Screen+face preview is blocked until capture interop lands.",
                    "Capture window not implemented yet.");
                break;
            case HotkeyCommand.QuickScreenFacePing:
                ShowBlockedState(
                    "Quick Screen+Face",
                    "Alt+Shift+L reached Ping. Quick send is blocked until default room and capture are available.",
                    "Needs room and capture implementation.");
                break;
            case HotkeyCommand.History:
                ShowHistory("Alt+O reached Ping. Room history shell is visible.");
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(command), command, "Unknown Ping hotkey command.");
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        hotkeys.HotkeyPressed -= HandleHotkeyPressed;
        hotkeys.Dispose();
        tray.Dispose();
        disposed = true;
    }

    private IReadOnlyList<HotkeyRegistrationResult> RegisterSavedHotkeys()
    {
        var bindings = preferencesStore.Load();
        var results = new List<HotkeyRegistrationResult>();
        foreach (var pair in bindings)
        {
            results.Add(hotkeys.Register(pair.Key, pair.Value));
        }

        return results;
    }

    private void ExecuteTrayCommand(TrayCommand command)
    {
        switch (command)
        {
            case TrayCommand.OpenPing:
                ShowHistory("Tray opened Ping.");
                break;
            case TrayCommand.NewFacePing:
                Execute(HotkeyCommand.FacePing);
                break;
            case TrayCommand.NewScreenFacePing:
                Execute(HotkeyCommand.ScreenFacePing);
                break;
            case TrayCommand.QuickScreenFacePing:
                Execute(HotkeyCommand.QuickScreenFacePing);
                break;
            case TrayCommand.Settings:
                ShowBlockedState(
                    "Settings",
                    "Settings is wired from the tray. Hotkey recording and account settings arrive in later tasks.",
                    "Settings window not implemented yet.");
                break;
            case TrayCommand.Quit:
                Application.Current.Exit();
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(command), command, "Unknown tray command.");
        }
    }

    private void HandleHotkeyPressed(object? sender, HotkeyCommand command)
    {
        Execute(command);
    }

    private void ShowHistory(string detail)
    {
        mainWindow.ShellTitle.Text = "Ping";
        mainWindow.StateBadge.Text = "History";
        mainWindow.StateTitle.Text = "Rooms and recent pings";
        mainWindow.StateDetail.Text = detail;
        mainWindow.StateBorder.BorderBrush = mainWindow.Resources["PingIdleBrush"] as Microsoft.UI.Xaml.Media.Brush;
        mainWindow.HistoryPanel.Visibility = Visibility.Visible;
        mainWindow.BlockedPanel.Visibility = Visibility.Collapsed;
        mainWindow.Activate();
    }

    private void ShowBlockedState(string title, string detail, string reason)
    {
        mainWindow.ShellTitle.Text = title;
        mainWindow.StateBadge.Text = "Blocked";
        mainWindow.StateTitle.Text = title;
        mainWindow.StateDetail.Text = detail;
        mainWindow.BlockedReason.Text = reason;
        mainWindow.StateBorder.BorderBrush = mainWindow.Resources["PingWarningBrush"] as Microsoft.UI.Xaml.Media.Brush;
        mainWindow.HistoryPanel.Visibility = Visibility.Collapsed;
        mainWindow.BlockedPanel.Visibility = Visibility.Visible;
        mainWindow.Activate();
    }

    private void ShowRegistrationState(IReadOnlyList<HotkeyRegistrationResult> registrations)
    {
        var failures = registrations
            .Where(result => result.Status != HotkeyRegistrationStatus.Success)
            .Select(result => $"{result.Binding}: {result.Message}")
            .ToArray();

        if (failures.Length == 0)
        {
            mainWindow.HotkeyState.Text = "Alt+P face, Alt+L screen+face, Alt+Shift+L quick send, Alt+O history";
            return;
        }

        mainWindow.HotkeyState.Text = string.Join(Environment.NewLine, failures);
    }
}
