using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Ping.Windows.App.UI;
#endif

namespace Ping.Windows.App.Playback;

public sealed class PlaybackViewModel : INotifyPropertyChanged
{
    public static readonly TimeSpan PausedTimeout = TimeSpan.FromSeconds(10);
    private const double FaceOnlyAspectRatio = 1;
    private const double ScreenFaceFallbackAspectRatio = 16.0 / 9.0;
    private const double MinimumScreenFacePlaybackAspectRatio = 0.5;
    private const double MaximumScreenFacePlaybackAspectRatio = 3.0;

    private readonly Func<CancellationToken, Task> markSeenAsync;
    private bool didMarkSeen;
    private bool isAwaitingDismissal;
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

    public event EventHandler? PlaybackEnded;

    public event EventHandler? ReplayRequested;

    public VideoMessage Message { get; }

    public string LocalVideoPath { get; }

    public bool IsScreenFace => Message.CaptureMode == CaptureMode.ScreenFace;

    public double AspectRatio
    {
        get
        {
            var fallback = IsScreenFace ? ScreenFaceFallbackAspectRatio : FaceOnlyAspectRatio;
            var ratio = Message.AspectRatio ?? fallback;
            if (!double.IsFinite(ratio) || ratio <= 0)
            {
                return fallback;
            }

            return IsScreenFace
                ? Math.Clamp(
                    ratio,
                    MinimumScreenFacePlaybackAspectRatio,
                    MaximumScreenFacePlaybackAspectRatio)
                : ratio;
        }
    }

    public string SenderLabel => Message.SenderNickname;

    public bool IsAwaitingDismissal
    {
        get => isAwaitingDismissal;
        private set
        {
            if (isAwaitingDismissal == value)
            {
                return;
            }

            isAwaitingDismissal = value;
            OnPropertyChanged();
        }
    }

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
                await markSeenAsync(cancellationToken);
                didMarkSeen = true;
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
        }

        if (IsAwaitingDismissal)
        {
            return;
        }

        IsAwaitingDismissal = true;
        PlaybackEnded?.Invoke(this, EventArgs.Empty);
    }

    public void HandleEnter()
    {
        if (!IsAwaitingDismissal)
        {
            return;
        }

        IsAwaitingDismissal = false;
        ReplayRequested?.Invoke(this, EventArgs.Empty);
    }

    public void HandlePausedTimeoutElapsed() => RequestClose();

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
    private CancellationTokenSource? closeTimeoutCancellation;
    private bool shouldCloseAfterFade;

    public PlaybackWindow(PlaybackViewModel viewModel)
    {
        this.viewModel = viewModel;
        InitializeComponent();
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
        viewModel.CloseRequested += HandleCloseRequested;
        viewModel.PlaybackEnded += HandlePlaybackEnded;
        viewModel.ReplayRequested += HandleReplayRequested;
        Closed += HandleClosed;
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
        switch (args.Key)
        {
            case global::Windows.System.VirtualKey.Enter:
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

                _ = Root.DispatcherQueue.TryEnqueue(() => viewModel.HandlePausedTimeoutElapsed());
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
        if (viewModel.IsScreenFace)
        {
            PlayerSurface.Clip = null;
        }
        else
        {
            RoundedCompositionClip.Apply(PlayerSurface, size.Width, size.Height, size.Width / 2d);
        }
        appWindow.Resize(size);
        appWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        appWindow.SetPresenter(AppWindowPresenterKind.CompactOverlay);
        MoveToMirrorPosition(size);
    }

    private global::Windows.Graphics.SizeInt32 PlaybackWindowSize()
    {
        if (!viewModel.IsScreenFace)
        {
            return new global::Windows.Graphics.SizeInt32(200, 200);
        }

        const int width = 480;
        var height = Math.Max(120, (int)Math.Round(width / viewModel.AspectRatio));
        return new global::Windows.Graphics.SizeInt32(width, height);
    }

    private void MoveToMirrorPosition(global::Windows.Graphics.SizeInt32 size)
    {
        if (appWindow is null)
        {
            return;
        }

        var area = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Primary);
        var workArea = area.WorkArea;
        var left = workArea.X + (int)Math.Round(workArea.Width * viewModel.Message.MirrorPosition.XRatio) - size.Width / 2;
        var top = workArea.Y + (int)Math.Round(workArea.Height * viewModel.Message.MirrorPosition.YRatio) - size.Height / 2;
        appWindow.Move(new global::Windows.Graphics.PointInt32(
            Math.Clamp(left, workArea.X, workArea.X + Math.Max(0, workArea.Width - size.Width)),
            Math.Clamp(top, workArea.Y, workArea.Y + Math.Max(0, workArea.Height - size.Height))));
    }

    private void HandleClosed(object sender, WindowEventArgs args)
    {
        viewModel.CloseRequested -= HandleCloseRequested;
        viewModel.PlaybackEnded -= HandlePlaybackEnded;
        viewModel.ReplayRequested -= HandleReplayRequested;
        CancelPausedCloseTimeout();
        playerHost.Dispose();
    }
}
#endif
