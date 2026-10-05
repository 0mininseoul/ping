using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Ping.Windows.App.History;
using Ping.Windows.App.UI;

namespace Ping.Windows.App;

public sealed partial class MainWindow : Window
{
    private AppWindow? appWindow;
    private bool allowClose;
    private HistoryWindow? messenger;
    private readonly MessengerWindowPlacementStore? placementStore;
    private MessengerWindowPlacementController? placement;
    public MainWindow() : this(DefaultPlacementStore()) { }
    internal MainWindow(MessengerWindowPlacementStore? placementStore)
    {
        this.placementStore = placementStore;
        InitializeComponent();
        Ping.Windows.App.UI.PingAppearance.Register(this);
        Ping.Windows.App.UI.WindowCaptureExclusion.Apply(this);
        Closed += (_, args) =>
        {
            if (allowClose) return;
            args.Handled = true;
            placement?.Flush();
            appWindow?.Hide();
        };
    }
    public event EventHandler? BlockedRetryRequested;
    public event EventHandler? OpenRoomsRequested;
    public event EventHandler? NewPingRequested;
    public event EventHandler? ScreenPingRequested;
    public event EventHandler? OpenSettingsRequested;

    public void AttachMessenger(HistoryWindow view)
    {
        if (messenger is not null) throw new InvalidOperationException("Ping already owns a messenger.");
        messenger = view;
        MessengerHost.Content = view;
        view.RoomsRequested += (_, _) => OpenRoomsRequested?.Invoke(this, EventArgs.Empty);
        view.FacePingRequested += (_, _) => NewPingRequested?.Invoke(this, EventArgs.Empty);
        view.ScreenPingRequested += (_, _) => ScreenPingRequested?.Invoke(this, EventArgs.Empty);
        view.SettingsRequested += (_, _) => OpenSettingsRequested?.Invoke(this, EventArgs.Empty);
        view.RetryRequested += (_, _) => BlockedRetryRequested?.Invoke(this, EventArgs.Empty);
    }

    public void DetachMessenger()
    {
        MessengerHost.Content = null;
        messenger = null;
    }

    public void InitializeTrayWindowBehavior()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        appWindow = AppWindow.GetFromWindowId(Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd));
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "Ping.ico");
        if (File.Exists(iconPath)) appWindow.SetIcon(iconPath);
        placement = new(appWindow, hwnd, placementStore);
        var restored = placement.Restore();
#if PING_UI_SMOKE
        if (!restored) Diagnostics.TestDisplayPlacement.Apply(this);
#else
        _ = restored;
#endif
        appWindow.Closing += HandleAppWindowClosing;
    }

    public void ShowShell() { appWindow?.Show(true); Activate(); }
    public void CloseForQuit() { placement?.Dispose(); allowClose = true; Close(); }
    public void ReportStatus(string? message, bool canRetry = false) => messenger?.ReportConnectionStatus(message, canRetry);
    public void SetHotkeyStatus(string message) => messenger?.SetHotkeyStatus(message);
    public void ConfigureQuickSendSettings(bool isEnabled, string defaultRoomLabel) => messenger?.SetDefaultRoom(defaultRoomLabel);
    private void HandleAppWindowClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (allowClose) return;
        args.Cancel = true;
        placement?.Flush();
        sender.Hide();
    }
    private static MessengerWindowPlacementStore? DefaultPlacementStore()
    {
#if PING_UI_SMOKE
        return null;
#else
        return new(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ping", "MessengerWindowPlacement.json"));
#endif
    }
}
