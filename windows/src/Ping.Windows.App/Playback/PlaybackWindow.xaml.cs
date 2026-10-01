using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Ping.Windows.App.UI;
using Ping.Windows.Core.Incoming;

namespace Ping.Windows.App.Playback;
public sealed partial class PlaybackWindow : Window
{
    private readonly PlaybackViewModel viewModel;
    private readonly VideoPlayerHost playerHost = new();
    private AppWindow? appWindow;
    private CancellationTokenSource? closeTimeoutCancellation;
    private bool shouldCloseAfterFade;
    private bool closed;
    private bool applyingPlacement;
    private readonly Window? owner;
    private readonly bool historyReplay;
    internal PlaybackViewModel ViewModel => viewModel;
    internal bool IsReplyGroupMember { get; set; }
    internal PlaybackRect WorkAreaDips { get; private set; }
    internal PlaybackRect Placement { get; private set; }
    private double scale = 1;

    public PlaybackWindow(PlaybackViewModel viewModel, Window? owner = null, bool historyReplay = false)
    {
        this.viewModel = viewModel;
        this.owner = owner;
        this.historyReplay = historyReplay;
        InitializeComponent();
        Ping.Windows.App.UI.PingAppearance.Register(this);
        Ping.Windows.App.UI.WindowCaptureExclusion.Apply(this);
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
        viewModel.CloseRequested += HandleCloseRequested;
        viewModel.PlaybackEnded += HandlePlaybackEnded;
        viewModel.ReplayRequested += HandleReplayRequested;
        ConfigureWindow();
    }

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        Root.Focus(FocusState.Programmatic);
        playerHost.Attach(PlayerElement, viewModel.LocalVideoPath, async token =>
        {
            await viewModel.HandlePlaybackEndedAsync(token);
        });
        playerHost.PlaybackFailed += HandlePlaybackFailed;
        await playerHost.PlayAsync();
    }

    private void HandleKeyDown(object sender, Microsoft.UI.Xaml.Input.KeyRoutedEventArgs args)
    {
        switch (args.Key)
        {
            case global::Windows.System.VirtualKey.Enter:
            case global::Windows.System.VirtualKey.Space:
                args.Handled = true;
                viewModel.HandleEnter();
                break;
            case global::Windows.System.VirtualKey.Escape:
                args.Handled = true;
                viewModel.HandleEscape();
                break;
        }
    }

    private void HandleCloseRequested(object? sender, EventArgs args)
    {
        if (shouldCloseAfterFade)
        {
            return;
        }

        _ = FadeOutAndCloseAsync();
    }

    private void HandlePlaybackEnded(object? sender, EventArgs args)
    {
        StartPausedCloseTimeout();
    }

    private void HandleReplayRequested(object? sender, EventArgs args)
    {
        CancelPausedCloseTimeout();
        playerHost.Replay();
    }

    private void StartPausedCloseTimeout()
    {
        CancelPausedCloseTimeout();
        closeTimeoutCancellation = new CancellationTokenSource();
        var token = closeTimeoutCancellation.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(PlaybackViewModel.PausedTimeout, token);
                if (token.IsCancellationRequested)
                {
                    return;
                }

                _ = Root.DispatcherQueue.TryEnqueue(() => { if (!closed && !token.IsCancellationRequested) viewModel.HandlePausedTimeoutElapsed(); });
            }
            catch (OperationCanceledException)
            {
            }
        }, token);
    }

    private void CancelPausedCloseTimeout()
    {
        closeTimeoutCancellation?.Cancel();
        closeTimeoutCancellation?.Dispose();
        closeTimeoutCancellation = null;
    }

    private async Task FadeOutAndCloseAsync()
    {
        CancelPausedCloseTimeout();
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
        if (!closed) Close();
    }

    private void ConfigureWindow()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
        appWindow = AppWindow.GetFromWindowId(windowId);
        var presenter = OverlappedPresenter.CreateForToolWindow();
        presenter.SetBorderAndTitleBar(false, false);
        presenter.IsAlwaysOnTop = true;
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        appWindow.SetPresenter(presenter);
        var area = owner is null ? DisplayArea.GetFromWindowId(windowId, DisplayAreaFallback.Primary)
            : DisplayArea.GetFromWindowId(owner.AppWindow.Id, DisplayAreaFallback.Primary);
        appWindow.Move(new global::Windows.Graphics.PointInt32(area.WorkArea.X + area.WorkArea.Width / 2, area.WorkArea.Y + area.WorkArea.Height / 2));
        ConfigurePlacement();
        appWindow.Changed += HandleWindowChanged;
    }

    private void ConfigurePlacement()
    {
        if (appWindow is null || closed) return;
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        scale = Math.Max(1, GetDpiForWindow(hwnd) / 96d);
        var area = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        WorkAreaDips = new(area.X / scale, area.Y / scale, area.Width / scale, area.Height / scale);
        PlaybackRect? parent = owner is null ? null : new(owner.AppWindow.Position.X / scale, owner.AppWindow.Position.Y / scale,
            owner.AppWindow.Size.Width / scale, owner.AppWindow.Size.Height / scale);
        ApplyPlacement(PlaybackLayout.Single(viewModel.Message.CaptureMode, viewModel.Message.AspectRatio, viewModel.Message.MirrorPosition,
            WorkAreaDips, historyReplay, parent));
    }

    internal void ApplyPlacement(PlaybackRect placement)
    {
        if (appWindow is null || closed) return;
        applyingPlacement = true;
        try
        {
            Placement = placement;
            Root.Width = placement.Width;
            Root.Height = placement.Height;
            PlaybackBorder.CornerRadius = viewModel.IsScreenFace
                ? new CornerRadius(16)
                : new CornerRadius(placement.Width / 2d);
            PlayerElement.Stretch = viewModel.IsScreenFace ? Stretch.Uniform : Stretch.UniformToFill;
            SenderChip.Visibility = viewModel.IsScreenFace ? Visibility.Visible : Visibility.Collapsed;
            if (viewModel.IsScreenFace)
            {
                PlayerSurface.Clip = null;
            }
            else
            {
                RoundedCompositionClip.Apply(PlayerSurface, placement.Width, placement.Height, placement.Width / 2d);
            }
            var width = Math.Max(1, (int)Math.Round(placement.Width * scale));
            var height = Math.Max(1, (int)Math.Round(placement.Height * scale));
            appWindow.ResizeClient(new global::Windows.Graphics.SizeInt32(width, height));
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            GetWindowRect(hwnd, out var outer);
            var clientOrigin = new NativePoint();
            ClientToScreen(hwnd, ref clientOrigin);
            var offsetX = clientOrigin.X - outer.Left;
            var offsetY = clientOrigin.Y - outer.Top;
            appWindow.Move(new global::Windows.Graphics.PointInt32((int)Math.Round(placement.X * scale) - offsetX, (int)Math.Round(placement.Y * scale) - offsetY));
            var region = viewModel.IsScreenFace ? CreateRoundRectRgn(offsetX, offsetY, offsetX + width + 1, offsetY + height + 1, (int)Math.Round(32 * scale), (int)Math.Round(32 * scale))
                : CreateEllipticRgn(offsetX, offsetY, offsetX + width + 1, offsetY + height + 1);
            if (region != IntPtr.Zero && SetWindowRgn(hwnd, region, true) == 0) DeleteObject(region);
        }
        finally { applyingPlacement = false; }
    }

    private void HandleWindowChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (closed || applyingPlacement) return;
        if (args.DidPositionChange && GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96d != scale) ConfigurePlacement();
    }

    private void HandlePlaybackFailed(object? sender, EventArgs args) => viewModel.HandleEscape();

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref NativePoint point);
    [DllImport("user32.dll")] private static extern int SetWindowRgn(IntPtr hwnd, IntPtr region, bool redraw);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateEllipticRgn(int left, int top, int right, int bottom);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateRoundRectRgn(int left, int top, int right, int bottom, int widthEllipse, int heightEllipse);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }

    private void HandleClosed(object sender, WindowEventArgs args)
    {
        closed = true;
        if (appWindow is not null) appWindow.Changed -= HandleWindowChanged;
        viewModel.CloseRequested -= HandleCloseRequested;
        viewModel.PlaybackEnded -= HandlePlaybackEnded;
        viewModel.ReplayRequested -= HandleReplayRequested;
        CancelPausedCloseTimeout();
        playerHost.PlaybackFailed -= HandlePlaybackFailed;
        playerHost.Dispose();
    }
}
