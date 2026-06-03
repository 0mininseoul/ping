using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using global::Windows.Graphics;
using Microsoft.UI.Xaml.Media;

namespace Ping.Windows.App;

public sealed partial class MainWindow : Window
{
    private const int InitialHomeWidth = 900;
    private const int InitialHomeHeight = 680;
    private const int MinimumHomeWidth = 760;
    private const int MinimumHomeHeight = 560;
    private const int DisplayMargin = 48;

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

        ResizeToInitialHomeSize();
        appWindow.Closing += HandleAppWindowClosing;
    }

    private void ResizeToInitialHomeSize()
    {
        if (appWindow is null)
        {
            return;
        }

        var area = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Nearest);
        var workArea = area.WorkArea;
        var width = ClampWindowDimension(InitialHomeWidth, MinimumHomeWidth, workArea.Width - DisplayMargin * 2);
        var height = ClampWindowDimension(InitialHomeHeight, MinimumHomeHeight, workArea.Height - DisplayMargin * 2);
        var left = workArea.X + Math.Max(0, (workArea.Width - width) / 2);
        var top = workArea.Y + Math.Max(0, (workArea.Height - height) / 2);
        appWindow.MoveAndResize(new RectInt32(left, top, width, height));
    }

    private static int ClampWindowDimension(int preferred, int minimum, int available)
    {
        if (available <= 0)
        {
            return minimum;
        }

        return Math.Max(Math.Min(preferred, available), Math.Min(minimum, available));
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

    private void HandleRootSizeChanged(object sender, SizeChangedEventArgs args)
    {
        var compact = args.NewSize.Width < 820;
        SelectedRoomPreview.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        CompactRoomsButton.Visibility = compact ? Visibility.Visible : Visibility.Collapsed;
        HomePreviewColumn.MinWidth = compact ? 0 : 240;
        HomePreviewColumn.Width = compact ? new GridLength(0) : new GridLength(1.05, GridUnitType.Star);
        HomeListColumn.Width = compact ? new GridLength(1, GridUnitType.Star) : new GridLength(0.95, GridUnitType.Star);
    }
}
