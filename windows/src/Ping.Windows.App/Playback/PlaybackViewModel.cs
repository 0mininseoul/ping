using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
#endif

namespace Ping.Windows.App.Playback;

public sealed class PlaybackViewModel : INotifyPropertyChanged
{
    private readonly Func<CancellationToken, Task> markSeenAsync;
    private bool didMarkSeen;
    private bool isCloseRequested;

    public PlaybackViewModel(
        VideoMessage message,
        string localVideoPath,
        Func<CancellationToken, Task> markSeenAsync)
    {
        Message = message;
        LocalVideoPath = localVideoPath;
        this.markSeenAsync = markSeenAsync;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public event EventHandler? CloseRequested;

    public VideoMessage Message { get; }

    public string LocalVideoPath { get; }

    public bool IsScreenFace => Message.CaptureMode == CaptureMode.ScreenFace;

    public double AspectRatio
    {
        get
        {
            var ratio = Message.AspectRatio ?? (IsScreenFace ? 16.0 / 9.0 : 1);
            return double.IsNaN(ratio) || double.IsInfinity(ratio) || ratio <= 0 ? 1 : ratio;
        }
    }

    public string SenderLabel => Message.SenderNickname;

    public bool IsCloseRequested
    {
        get => isCloseRequested;
        private set
        {
            if (isCloseRequested == value)
            {
                return;
            }

            isCloseRequested = value;
            OnPropertyChanged();
        }
    }

    public async Task HandlePlaybackEndedAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            if (!didMarkSeen && Message.Id is not null)
            {
                didMarkSeen = true;
                await markSeenAsync(cancellationToken);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
        }

        RequestClose();
    }

    public void HandleEscape() => RequestClose();

    private void RequestClose()
    {
        IsCloseRequested = true;
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

#if WINDOWS
public sealed partial class PlaybackWindow : Window
{
    private readonly PlaybackViewModel viewModel;
    private readonly VideoPlayerHost playerHost = new();
    private AppWindow? appWindow;
    private bool shouldCloseAfterFade;

    public PlaybackWindow(PlaybackViewModel viewModel)
    {
        this.viewModel = viewModel;
        InitializeComponent();
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
        viewModel.CloseRequested += HandleCloseRequested;
        ConfigureWindow();
    }

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        Root.Focus(FocusState.Programmatic);
        playerHost.Attach(PlayerElement, viewModel.LocalVideoPath, async token =>
        {
            await viewModel.HandlePlaybackEndedAsync(token);
        });
        await playerHost.PlayAsync();
    }

    private void HandleKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs args)
    {
        if (args.Key != Windows.System.VirtualKey.Escape)
        {
            return;
        }

        args.Handled = true;
        viewModel.HandleEscape();
    }

    private void HandleCloseRequested(object? sender, EventArgs args)
    {
        if (shouldCloseAfterFade)
        {
            return;
        }

        _ = FadeOutAndCloseAsync();
    }

    private async Task FadeOutAndCloseAsync()
    {
        shouldCloseAfterFade = true;
        var animation = new DoubleAnimation
        {
            To = 0,
            Duration = new Duration(TimeSpan.FromMilliseconds(300))
        };
        Storyboard.SetTarget(animation, Root);
        Storyboard.SetTargetProperty(animation, nameof(Root.Opacity));
        var storyboard = new Storyboard();
        storyboard.Children.Add(animation);
        var completed = new TaskCompletionSource();
        storyboard.Completed += (_, _) => completed.SetResult();
        storyboard.Begin();
        await completed.Task;
        Close();
    }

    private void ConfigureWindow()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
        appWindow = AppWindow.GetFromWindowId(windowId);
        var size = PlaybackWindowSize();
        Root.Width = size.Width;
        Root.Height = size.Height;
        PlaybackBorder.CornerRadius = viewModel.IsScreenFace
            ? new CornerRadius(16)
            : new CornerRadius(size.Width / 2d);
        PlayerElement.Stretch = viewModel.IsScreenFace ? Stretch.Uniform : Stretch.UniformToFill;
        SenderChip.Visibility = viewModel.IsScreenFace ? Visibility.Visible : Visibility.Collapsed;
        PlayerSurface.Clip = viewModel.IsScreenFace
            ? null
            : new EllipseGeometry
            {
                Center = new Windows.Foundation.Point(size.Width / 2d, size.Height / 2d),
                RadiusX = size.Width / 2d,
                RadiusY = size.Height / 2d
            };
        appWindow.Resize(size);
        appWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        appWindow.SetPresenter(AppWindowPresenterKind.CompactOverlay);
        MoveToMirrorPosition(size);
    }

    private Windows.Graphics.SizeInt32 PlaybackWindowSize()
    {
        if (!viewModel.IsScreenFace)
        {
            return new Windows.Graphics.SizeInt32(200, 200);
        }

        const int width = 420;
        var height = Math.Max(120, (int)Math.Round(width / viewModel.AspectRatio));
        return new Windows.Graphics.SizeInt32(width, height);
    }

    private void MoveToMirrorPosition(Windows.Graphics.SizeInt32 size)
    {
        if (appWindow is null)
        {
            return;
        }

        var area = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Primary);
        var workArea = area.WorkArea;
        var left = workArea.X + (int)Math.Round(workArea.Width * viewModel.Message.MirrorPosition.XRatio) - size.Width / 2;
        var top = workArea.Y + (int)Math.Round(workArea.Height * viewModel.Message.MirrorPosition.YRatio) - size.Height / 2;
        appWindow.Move(new Windows.Graphics.PointInt32(
            Math.Clamp(left, workArea.X, workArea.X + Math.Max(0, workArea.Width - size.Width)),
            Math.Clamp(top, workArea.Y, workArea.Y + Math.Max(0, workArea.Height - size.Height))));
    }

    private void HandleClosed(object sender, WindowEventArgs args)
    {
        playerHost.Dispose();
    }
}
#endif
