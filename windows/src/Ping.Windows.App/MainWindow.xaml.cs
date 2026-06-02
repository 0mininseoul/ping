using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace Ping.Windows.App;

public sealed partial class MainWindow : Window
{
    private AppWindow? appWindow;
    private bool allowClose;
    private bool isUpdatingSettingsControls;

    public MainWindow()
    {
        InitializeComponent();
    }

    public Brush? IdleBorderBrush => Root.Resources["PingIdleBrush"] as Brush;

    public Brush? WarningBorderBrush => Root.Resources["PingWarningBrush"] as Brush;

    public event EventHandler<bool>? QuickSendToggleChanged;

    public event EventHandler? BlockedRetryRequested;

    public event EventHandler? OpenRoomsRequested;

    public event EventHandler? OpenHistoryRequested;

    public event EventHandler? NewPingRequested;

    public event EventHandler? OpenSettingsRequested;

    public void InitializeTrayWindowBehavior()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        appWindow = AppWindow.GetFromWindowId(windowId);
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "Ping.ico");
        if (File.Exists(iconPath))
        {
            appWindow.SetIcon(iconPath);
        }

        appWindow.Closing += HandleAppWindowClosing;
    }

    public void ShowShell()
    {
        appWindow?.Show(true);
        Activate();
    }

    public void ConfigureQuickSendSettings(bool isEnabled, string defaultRoomLabel)
    {
        isUpdatingSettingsControls = true;
        try
        {
            QuickSendToggle.IsOn = isEnabled;
            QuickSendDefaultRoom.Text = defaultRoomLabel;
        }
        finally
        {
            isUpdatingSettingsControls = false;
        }
    }

    public void CloseForQuit()
    {
        allowClose = true;
        Close();
    }

    private void HandleAppWindowClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (allowClose)
        {
            return;
        }

        args.Cancel = true;
        sender.Hide();
    }

    private void HandleQuickSendToggleToggled(object sender, RoutedEventArgs args)
    {
        if (isUpdatingSettingsControls)
        {
            return;
        }

        QuickSendToggleChanged?.Invoke(this, QuickSendToggle.IsOn);
    }

    private void HandleBlockedRetryClicked(object sender, RoutedEventArgs args)
    {
        BlockedRetryRequested?.Invoke(this, EventArgs.Empty);
    }

    private void HandleOpenRoomsClicked(object sender, RoutedEventArgs args)
    {
        OpenRoomsRequested?.Invoke(this, EventArgs.Empty);
    }

    private void HandleOpenHistoryClicked(object sender, RoutedEventArgs args)
    {
        OpenHistoryRequested?.Invoke(this, EventArgs.Empty);
    }

    private void HandleNewPingClicked(object sender, RoutedEventArgs args)
    {
        NewPingRequested?.Invoke(this, EventArgs.Empty);
    }

    private void HandleOpenSettingsClicked(object sender, RoutedEventArgs args)
    {
        OpenSettingsRequested?.Invoke(this, EventArgs.Empty);
    }
}
