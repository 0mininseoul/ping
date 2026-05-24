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

    public void InitializeTrayWindowBehavior()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        appWindow = AppWindow.GetFromWindowId(windowId);
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
}
