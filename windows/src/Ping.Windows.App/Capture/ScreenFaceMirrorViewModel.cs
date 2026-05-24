using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.LocalState;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
#endif

namespace Ping.Windows.App.Capture;

public sealed record ScreenFaceMirrorContext(
    IReadOnlyCollection<Room> Rooms,
    string SenderUid,
    string SenderNickname,
    string PartnerLabel,
    bool AllowsLocalSave,
    bool SaveSentCopy);

public sealed class ScreenFaceMirrorViewModel : INotifyPropertyChanged
{
    private static readonly TimeSpan RecordingDuration = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan PreviewRefreshInterval = TimeSpan.FromMilliseconds(700);

    private readonly ScreenFaceMirrorContext context;
    private readonly IScreenFaceCaptureEngine captureEngine;
    private readonly Func<SendVideoInput, CancellationToken, Task> sendAsync;
    private readonly LocalArchive? archive;
    private CancellationTokenSource? operationCancellation;
    private MirrorState state = MirrorState.Idle;
    private string statusMessage = "Press Enter to record.";
    private Uri? screenPreviewUri;
    private string? screenPreviewPath;
    private MirrorPosition mirrorPosition = new(0.5, 0.5);
    private bool isCloseRequested;
    private bool isFadeOutRequested;

    public ScreenFaceMirrorViewModel(
        ScreenFaceMirrorContext context,
        IScreenFaceCaptureEngine captureEngine,
        MessageService messageService,
        LocalArchive? archive = null)
        : this(context, captureEngine, messageService.SendAsync, archive)
    {
    }

    public ScreenFaceMirrorViewModel(
        ScreenFaceMirrorContext context,
        IScreenFaceCaptureEngine captureEngine,
        Func<SendVideoInput, CancellationToken, Task> sendAsync,
        LocalArchive? archive = null)
    {
        this.context = context;
        this.captureEngine = captureEngine;
        this.sendAsync = sendAsync;
        this.archive = archive;
        PartnerLabel = string.IsNullOrWhiteSpace(context.PartnerLabel) ? "No partner" : context.PartnerLabel;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public event EventHandler? CloseRequested;

    public event EventHandler? FadeOutRequested;

    public MirrorState State
    {
        get => state;
        private set
        {
            if (state == value)
            {
                return;
            }

            state = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(StateText));
            OnPropertyChanged(nameof(CanRecord));
        }
    }

    public string StateText => State switch
    {
        MirrorState.Idle => "Ready",
        MirrorState.Recording => "Recording",
        MirrorState.Uploading => "Sending",
        MirrorState.Failed => "Failed",
        _ => throw new ArgumentOutOfRangeException(nameof(State), State, "Unknown mirror state.")
    };

    public string StatusMessage
    {
        get => statusMessage;
        private set
        {
            if (string.Equals(statusMessage, value, StringComparison.Ordinal))
            {
                return;
            }

            statusMessage = value;
            OnPropertyChanged();
        }
    }

    public string PartnerLabel { get; }

    public Uri? ScreenPreviewUri
    {
        get => screenPreviewUri;
        private set
        {
            if (Equals(screenPreviewUri, value))
            {
                return;
            }

            screenPreviewUri = value;
            OnPropertyChanged();
        }
    }

    public bool CanRecord => State is MirrorState.Idle or MirrorState.Failed;

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

    public bool IsFadeOutRequested
    {
        get => isFadeOutRequested;
        private set
        {
            if (isFadeOutRequested == value)
            {
                return;
            }

            isFadeOutRequested = value;
            OnPropertyChanged();
        }
    }

    public void UpdateMirrorPosition(double centerX, double centerY, double displayWidth, double displayHeight)
    {
        if (displayWidth <= 0 || displayHeight <= 0)
        {
            mirrorPosition = new MirrorPosition(0.5, 0.5);
            return;
        }

        mirrorPosition = new MirrorPosition(
            ClampRatio(centerX / displayWidth),
            ClampRatio(centerY / displayHeight));
    }

    public async Task LoadPreviewAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var preview = await captureEngine.CapturePreviewAsync(monitorIndex: 0, cancellationToken);
            DisposePreview();
            screenPreviewPath = preview.FilePath;
            ScreenPreviewUri = new Uri(preview.FilePath);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            StatusMessage = $"Preview unavailable. Press Enter to record. {ex.Message}";
        }
    }

    public async Task RunPreviewLoopAsync(CancellationToken cancellationToken = default)
    {
        while (!cancellationToken.IsCancellationRequested && !IsCloseRequested)
        {
            if (State is MirrorState.Idle or MirrorState.Failed)
            {
                await LoadPreviewAsync(cancellationToken);
            }

            await Task.Delay(PreviewRefreshInterval, cancellationToken);
        }
    }

    public async Task HandleEnterAsync()
    {
        if (!CanRecord)
        {
            return;
        }

        operationCancellation?.Dispose();
        operationCancellation = new CancellationTokenSource();
        var cancellationToken = operationCancellation.Token;
        string? recordedPath = null;
        var sent = false;

        try
        {
            State = MirrorState.Recording;
            StatusMessage = "Recording screen and face...";
            var recording = await captureEngine.RecordAsync(RecordingDuration, monitorIndex: 0, cancellationToken);
            recordedPath = recording.FilePath;

            State = MirrorState.Uploading;
            StatusMessage = "Sending...";

            if (context.SaveSentCopy)
            {
                if (archive is null)
                {
                    throw new InvalidOperationException("Local archive is required when sent-copy saving is enabled.");
                }

                _ = await archive.SaveSentCopyAsync(
                    recordedPath,
                    LocalArchiveKind.Sent,
                    context.PartnerLabel,
                    cancellationToken: cancellationToken);
            }

            await sendAsync(
                new SendVideoInput(
                    context.Rooms,
                    recordedPath,
                    mirrorPosition,
                    context.SenderUid,
                    context.SenderNickname,
                    CaptureMode.ScreenFace,
                    recording.AspectRatio,
                    context.AllowsLocalSave),
                cancellationToken);
            sent = true;
            RequestFadeOutClose();
        }
        catch (OperationCanceledException) when (IsCloseRequested)
        {
        }
        catch (Exception exception)
        {
            State = MirrorState.Failed;
            StatusMessage = $"Could not send. Press Enter to retry. {exception.Message}";
        }
        finally
        {
            operationCancellation?.Dispose();
            operationCancellation = null;

            if (sent && recordedPath is not null)
            {
                TryDeleteTemporaryRecording(recordedPath);
            }
        }
    }

    public void HandleEscape()
    {
        operationCancellation?.Cancel();
        RequestClose();
    }

    public void DisposePreview()
    {
        ScreenPreviewUri = null;
        if (screenPreviewPath is null)
        {
            return;
        }

        TryDeleteTemporaryRecording(screenPreviewPath);
        screenPreviewPath = null;
    }

    private void RequestClose()
    {
        IsCloseRequested = true;
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void RequestFadeOutClose()
    {
        IsFadeOutRequested = true;
        FadeOutRequested?.Invoke(this, EventArgs.Empty);
        RequestClose();
    }

    private static double ClampRatio(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value))
        {
            return 0.5;
        }

        return Math.Max(0, Math.Min(1, value));
    }

    private static void TryDeleteTemporaryRecording(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

#if WINDOWS
public sealed partial class ScreenFaceMirrorWindow : Window
{
    private readonly ScreenFaceMirrorViewModel viewModel;
    private readonly FaceRecorder previewRecorder = new();
    private CancellationTokenSource? previewLoopCancellation;
    private Task? previewLoopTask;
    private AppWindow? appWindow;
    private bool shouldCloseAfterFade;

    public ScreenFaceMirrorWindow(ScreenFaceMirrorViewModel viewModel)
    {
        this.viewModel = viewModel;
        InitializeComponent();
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
        viewModel.PropertyChanged += HandleViewModelPropertyChanged;
        viewModel.FadeOutRequested += HandleFadeOutRequested;
        viewModel.CloseRequested += HandleCloseRequested;
        SetStateBrush();
        ConfigureWindow();
    }

    private async void HandleKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == Windows.System.VirtualKey.Enter)
        {
            args.Handled = true;
            await StopPreviewAsync();
            await viewModel.HandleEnterAsync();
            if (!viewModel.IsCloseRequested)
            {
                _ = StartPreviewAsync();
            }

            return;
        }

        if (args.Key == Windows.System.VirtualKey.Escape)
        {
            args.Handled = true;
            viewModel.HandleEscape();
        }
    }

    private void HandleLoaded(object sender, RoutedEventArgs args)
    {
        Root.Focus(FocusState.Programmatic);
        UpdatePositionFromWindow();
        _ = StartPreviewAsync();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(ScreenFaceMirrorViewModel.State))
        {
            SetStateBrush();
        }

        if (args.PropertyName == nameof(ScreenFaceMirrorViewModel.ScreenPreviewUri))
        {
            ScreenPreviewPlaceholder.Visibility =
                viewModel.ScreenPreviewUri is null ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void HandleCloseRequested(object? sender, EventArgs args)
    {
        if (shouldCloseAfterFade)
        {
            return;
        }

        Close();
    }

    private async void HandleFadeOutRequested(object? sender, EventArgs args)
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
        appWindow.Resize(new Windows.Graphics.SizeInt32(390, 300));
        appWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        appWindow.SetPresenter(AppWindowPresenterKind.CompactOverlay);
        UpdatePositionFromWindow();
        appWindow.Changed += (_, args) =>
        {
            if (args.DidPositionChange || args.DidSizeChange)
            {
                UpdatePositionFromWindow();
            }
        };
    }

    private void UpdatePositionFromWindow()
    {
        if (appWindow is null)
        {
            return;
        }

        var area = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Primary);
        var workArea = area.WorkArea;
        var position = appWindow.Position;
        var size = appWindow.Size;
        viewModel.UpdateMirrorPosition(
            position.X + size.Width / 2d - workArea.X,
            position.Y + size.Height / 2d - workArea.Y,
            workArea.Width,
            workArea.Height);
    }

    private async Task StartPreviewAsync()
    {
        if (previewLoopCancellation is not null)
        {
            await StopPreviewAsync();
        }

        previewLoopCancellation = new CancellationTokenSource();
        var token = previewLoopCancellation.Token;

        previewLoopTask = viewModel.RunPreviewLoopAsync(token);
        try
        {
            await previewRecorder.StartPreviewAsync(FacePreviewElement, token);
            FacePreviewPlaceholder.Visibility = Visibility.Collapsed;
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception) when (!token.IsCancellationRequested)
        {
            FacePreviewPlaceholder.Visibility = Visibility.Visible;
        }

        _ = previewLoopTask.ContinueWith(
            task =>
            {
                _ = task.Exception;
            },
            CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted,
            TaskScheduler.Default);
    }

    private async Task StopPreviewAsync()
    {
        var cancellation = previewLoopCancellation;
        var previewTask = previewLoopTask;
        previewLoopCancellation = null;
        previewLoopTask = null;
        cancellation?.Cancel();
        if (previewTask is not null)
        {
            try
            {
                await previewTask;
            }
            catch (OperationCanceledException)
            {
            }
        }

        cancellation?.Dispose();
        try
        {
            await previewRecorder.StopPreviewAsync(FacePreviewElement);
        }
        catch (Exception)
        {
        }
    }

    private async void HandleClosed(object sender, WindowEventArgs args)
    {
        await StopPreviewAsync();
        viewModel.DisposePreview();
    }

    private void SetStateBrush()
    {
        var key = viewModel.State switch
        {
            MirrorState.Idle => "PingBorderIdleBrush",
            MirrorState.Recording => "PingBorderRecordingBrush",
            MirrorState.Uploading => "PingRainbowBorderBrush",
            MirrorState.Failed => "PingBorderFailedBrush",
            _ => "PingBorderIdleBrush"
        };

        var thickness = viewModel.State == MirrorState.Idle ? 1 : 2;
        MirrorBorder.BorderBrush = Root.Resources[key] as Brush;
        MirrorBorder.BorderThickness = new Thickness(thickness);
    }
}
#endif
