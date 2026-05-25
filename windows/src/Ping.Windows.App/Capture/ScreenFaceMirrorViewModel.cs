using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.LocalState;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Media.Core;
using Windows.Media.Playback;
#endif

namespace Ping.Windows.App.Capture;

public sealed record ScreenFaceMirrorContext(
    IReadOnlyCollection<Room> Rooms,
    string SenderUid,
    string SenderNickname,
    string PartnerLabel,
    bool AllowsLocalSave,
    bool SaveSentCopy,
    int MonitorIndex = MonitorTargetResolver.DefaultMonitorIndex,
    MirrorPosition? InitialPosition = null,
    Action<MirrorPosition>? SaveMirrorPosition = null);

public sealed class ScreenFaceMirrorViewModel : INotifyPropertyChanged
{
    private static readonly TimeSpan RecordingDuration = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan PreviewRefreshInterval = TimeSpan.FromMilliseconds(700);

    private readonly ScreenFaceMirrorContext context;
    private readonly IScreenFaceCaptureEngine captureEngine;
    private readonly Func<SendVideoInput, CancellationToken, Task> sendAsync;
    private readonly LocalArchive? archive;
    private readonly MirrorTargetSelector targetSelector;
    private CancellationTokenSource? operationCancellation;
    private MirrorState state = MirrorState.Idle;
    private string statusMessage = "Press Enter to record.";
    private string recordingCountdownText = "3";
    private string partnerLabel;
    private Uri? screenPreviewUri;
    private string? screenPreviewPath;
    private Uri? reviewVideoUri;
    private string? reviewedPath;
    private double reviewedAspectRatio = 16.0 / 9.0;
    private MirrorPosition mirrorPosition = new(0.5, 0.5);
    private int monitorIndex;
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
        targetSelector = new MirrorTargetSelector(context.Rooms, context.PartnerLabel);
        partnerLabel = targetSelector.Label;
        monitorIndex = context.MonitorIndex;
        mirrorPosition = NormalizePosition(context.InitialPosition) ?? mirrorPosition;
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
            OnPropertyChanged(nameof(CanSelectTarget));
            OnPropertyChanged(nameof(RecordingCountdownOpacity));
        }
    }

    public string StateText => State switch
    {
        MirrorState.Idle => "Ready",
        MirrorState.Recording => "Recording",
        MirrorState.Reviewing => "Review",
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

    public string RecordingCountdownText
    {
        get => recordingCountdownText;
        private set
        {
            if (string.Equals(recordingCountdownText, value, StringComparison.Ordinal))
            {
                return;
            }

            recordingCountdownText = value;
            OnPropertyChanged();
        }
    }

    public double RecordingCountdownOpacity => State == MirrorState.Recording ? 1 : 0;

    public string PartnerLabel
    {
        get => partnerLabel;
        private set
        {
            if (string.Equals(partnerLabel, value, StringComparison.Ordinal))
            {
                return;
            }

            partnerLabel = value;
            OnPropertyChanged();
        }
    }

    public bool IsAllTargetsSelected => targetSelector.IsAllSelected;

    public bool HasTargetMenu => targetSelector.HasMultipleTargets;

    public IReadOnlyList<MirrorTargetOption> TargetOptions => targetSelector.Options;

    public Uri? ReviewVideoUri
    {
        get => reviewVideoUri;
        private set
        {
            if (Equals(reviewVideoUri, value))
            {
                return;
            }

            reviewVideoUri = value;
            OnPropertyChanged();
        }
    }

    public MirrorPosition MirrorPosition => mirrorPosition;

    public int MonitorIndex => monitorIndex;

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

    public bool CanRecord => State == MirrorState.Idle || (State == MirrorState.Failed && !HasReviewedClip);

    public bool CanSelectTarget => State is MirrorState.Idle or MirrorState.Reviewing or MirrorState.Failed;

    public bool HasReviewedClip => reviewedPath is not null;

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

    public bool SelectNextTarget() => CanSelectTarget && UpdateTarget(targetSelector.SelectNext());

    public bool SelectAllTargets() => CanSelectTarget && UpdateTarget(targetSelector.SelectAll());

    public bool SelectTargetAtIndex(int index) => CanSelectTarget && UpdateTarget(targetSelector.SelectIndex(index));

    public bool SelectTargetOption(MirrorTargetOption option) => CanSelectTarget && UpdateTarget(targetSelector.SelectOption(option));

    public void UpdateCaptureMonitor(int index)
    {
        if (monitorIndex == index)
        {
            return;
        }

        monitorIndex = index;
        OnPropertyChanged(nameof(MonitorIndex));
    }

    public void UpdateMirrorPosition(double centerX, double centerY, double displayWidth, double displayHeight)
    {
        if (displayWidth <= 0 || displayHeight <= 0)
        {
            mirrorPosition = new MirrorPosition(0.5, 0.5);
            OnPropertyChanged(nameof(MirrorPosition));
            context.SaveMirrorPosition?.Invoke(mirrorPosition);
            return;
        }

        mirrorPosition = new MirrorPosition(
            ClampRatio(centerX / displayWidth),
            ClampRatio(centerY / displayHeight));
        OnPropertyChanged(nameof(MirrorPosition));
        context.SaveMirrorPosition?.Invoke(mirrorPosition);
    }

    public async Task LoadPreviewAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var preview = await captureEngine.CapturePreviewAsync(monitorIndex, cancellationToken);
            DisposePreview();
            screenPreviewPath = preview.FilePath;
            ScreenPreviewUri = new Uri(preview.FilePath);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            DisposePreview();
            StatusMessage = $"Preview unavailable. Press Enter to record. {ex.Message}";
        }
    }

    public async Task RunPreviewLoopAsync(CancellationToken cancellationToken = default)
    {
        while (!cancellationToken.IsCancellationRequested && !IsCloseRequested)
        {
            if (State == MirrorState.Idle || (State == MirrorState.Failed && !HasReviewedClip))
            {
                await LoadPreviewAsync(cancellationToken);
            }

            await Task.Delay(PreviewRefreshInterval, cancellationToken);
        }
    }

    public async Task HandleEnterAsync()
    {
        if (State == MirrorState.Reviewing || (State == MirrorState.Failed && HasReviewedClip))
        {
            await UploadReviewedClipAsync();
            return;
        }

        if (!CanRecord)
        {
            return;
        }

        operationCancellation?.Dispose();
        operationCancellation = new CancellationTokenSource();
        var cancellationToken = operationCancellation.Token;
        string? recordedPath = null;
        CancellationTokenSource? countdownCancellation = null;
        Task? countdownTask = null;

        try
        {
            State = MirrorState.Recording;
            countdownCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            countdownTask = RunRecordingCountdownAsync(countdownCancellation.Token);
            var recording = await captureEngine.RecordAsync(RecordingDuration, monitorIndex, cancellationToken);
            await StopRecordingCountdownAsync(countdownCancellation, countdownTask);
            countdownCancellation = null;
            countdownTask = null;
            recordedPath = recording.FilePath;
            cancellationToken.ThrowIfCancellationRequested();

            EnterReview(recordedPath, recording.AspectRatio);
            recordedPath = null;
        }
        catch (OperationCanceledException) when (IsCloseRequested)
        {
        }
        catch (Exception exception)
        {
            State = MirrorState.Failed;
            StatusMessage = $"Could not record. Press Enter to retry. {exception.Message}";
        }
        finally
        {
            await StopRecordingCountdownAsync(countdownCancellation, countdownTask);
            operationCancellation?.Dispose();
            operationCancellation = null;

            if (recordedPath is not null)
            {
                TryDeleteTemporaryRecording(recordedPath);
            }
        }
    }

    public async Task HandleRedoAsync()
    {
        if (State != MirrorState.Reviewing && !(State == MirrorState.Failed && HasReviewedClip))
        {
            return;
        }

        ClearReviewedClip(deleteFile: true);
        await HandleEnterAsync();
    }

    private async Task UploadReviewedClipAsync()
    {
        if (reviewedPath is not { Length: > 0 } path)
        {
            return;
        }

        operationCancellation?.Dispose();
        operationCancellation = new CancellationTokenSource();
        var cancellationToken = operationCancellation.Token;
        var sent = false;

        try
        {
            State = MirrorState.Uploading;
            StatusMessage = "Sending...";

            await sendAsync(
                new SendVideoInput(
                    targetSelector.SelectedRooms,
                    path,
                    mirrorPosition,
                    context.SenderUid,
                    context.SenderNickname,
                    CaptureMode.ScreenFace,
                    reviewedAspectRatio,
                    context.AllowsLocalSave),
                cancellationToken);
            sent = true;
            await TrySaveSentCopyAsync(path, PartnerLabel);
            ClearReviewedClip(deleteFile: false);
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

            if (sent)
            {
                TryDeleteTemporaryRecording(path);
            }
        }
    }

    private async Task TrySaveSentCopyAsync(string path, string label)
    {
        if (!context.SaveSentCopy || archive is null)
        {
            return;
        }

        try
        {
            _ = await archive.SaveSentCopyAsync(
                path,
                LocalArchiveKind.Sent,
                label,
                cancellationToken: CancellationToken.None);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
        }
    }

    private async Task RunRecordingCountdownAsync(CancellationToken cancellationToken)
    {
        try
        {
            for (var secondsRemaining = (int)Math.Ceiling(RecordingDuration.TotalSeconds);
                 secondsRemaining > 0 && State == MirrorState.Recording;
                 secondsRemaining--)
            {
                RecordingCountdownText = secondsRemaining.ToString();
                StatusMessage = $"Recording {secondsRemaining}...";
                await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    private static async Task StopRecordingCountdownAsync(CancellationTokenSource? cancellation, Task? task)
    {
        if (cancellation is null)
        {
            return;
        }

        try
        {
            cancellation.Cancel();
            if (task is not null)
            {
                await task;
            }
        }
        finally
        {
            cancellation.Dispose();
        }
    }

    public void HandleEscape()
    {
        operationCancellation?.Cancel();
        ClearReviewedClip(deleteFile: true);
        RequestClose();
    }

    public void HandleWindowClosed()
    {
        operationCancellation?.Cancel();
        ClearReviewedClip(deleteFile: true);
        DisposePreview();
        IsCloseRequested = true;
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

    private void EnterReview(string path, double aspectRatio)
    {
        reviewedPath = path;
        reviewedAspectRatio = NormalizeAspectRatio(aspectRatio);
        ReviewVideoUri = new Uri(path);
        OnPropertyChanged(nameof(HasReviewedClip));
        OnPropertyChanged(nameof(CanRecord));
        State = MirrorState.Reviewing;
        StatusMessage = "Press Enter to send. Backspace to redo.";
    }

    private void ClearReviewedClip(bool deleteFile)
    {
        var path = reviewedPath;
        reviewedPath = null;
        reviewedAspectRatio = 16.0 / 9.0;
        ReviewVideoUri = null;
        OnPropertyChanged(nameof(HasReviewedClip));
        OnPropertyChanged(nameof(CanRecord));
        if (deleteFile && path is not null)
        {
            TryDeleteTemporaryRecording(path);
        }
    }

    private static double NormalizeAspectRatio(double aspectRatio) =>
        double.IsNaN(aspectRatio) || double.IsInfinity(aspectRatio) || aspectRatio <= 0
            ? 16.0 / 9.0
            : aspectRatio;

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

    private bool UpdateTarget(bool didChange)
    {
        if (!didChange)
        {
            return false;
        }

        PartnerLabel = targetSelector.Label;
        OnPropertyChanged(nameof(IsAllTargetsSelected));
        return true;
    }

    private static double ClampRatio(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value))
        {
            return 0.5;
        }

        return Math.Max(0, Math.Min(1, value));
    }

    private static MirrorPosition? NormalizePosition(MirrorPosition? position) =>
        position is null
            ? null
            : new MirrorPosition(
                ClampRatio(position.XRatio),
                ClampRatio(position.YRatio));

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
    private MediaPlayer? reviewPlayer;
    private AppWindow? appWindow;
    private IntPtr windowHandle;
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
        Closed += HandleClosed;
        SetStateBrush();
        ConfigureWindow();
    }

    private async void HandleKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (HandleTargetKey(args.Key))
        {
            args.Handled = true;
            return;
        }

        if (args.Key == Windows.System.VirtualKey.Enter)
        {
            args.Handled = true;
            if (viewModel.State != MirrorState.Reviewing)
            {
                await StopPreviewAsync();
            }

            await viewModel.HandleEnterAsync();
            if (!viewModel.IsCloseRequested && !viewModel.HasReviewedClip)
            {
                _ = StartPreviewAsync();
            }

            return;
        }

        if (args.Key == Windows.System.VirtualKey.Back
            || args.Key == Windows.System.VirtualKey.Delete)
        {
            args.Handled = true;
            await viewModel.HandleRedoAsync();
            if (!viewModel.IsCloseRequested && !viewModel.HasReviewedClip)
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

    private bool HandleTargetKey(Windows.System.VirtualKey key)
    {
        switch (key)
        {
            case Windows.System.VirtualKey.Tab:
                return viewModel.SelectNextTarget();
            case Windows.System.VirtualKey.A:
            case Windows.System.VirtualKey.Number0:
            case Windows.System.VirtualKey.NumberPad0:
                return viewModel.SelectAllTargets();
        }

        var keyValue = (int)key;
        if (keyValue >= (int)Windows.System.VirtualKey.Number1
            && keyValue <= (int)Windows.System.VirtualKey.Number9)
        {
            return viewModel.SelectTargetAtIndex(keyValue - (int)Windows.System.VirtualKey.Number1);
        }

        if (keyValue >= (int)Windows.System.VirtualKey.NumberPad1
            && keyValue <= (int)Windows.System.VirtualKey.NumberPad9)
        {
            return viewModel.SelectTargetAtIndex(keyValue - (int)Windows.System.VirtualKey.NumberPad1);
        }

        return false;
    }

    private void PartnerChip_Tapped(object sender, TappedRoutedEventArgs args)
    {
        if (!viewModel.CanSelectTarget || !viewModel.HasTargetMenu)
        {
            return;
        }

        var flyout = new MenuFlyout();
        foreach (var option in viewModel.TargetOptions)
        {
            var item = new MenuFlyoutItem
            {
                Text = option.Label
            };
            item.Click += (_, _) => viewModel.SelectTargetOption(option);
            flyout.Items.Add(item);
        }

        flyout.ShowAt(PartnerChip);
        args.Handled = true;
    }

    private void HandleLoaded(object sender, RoutedEventArgs args)
    {
        Root.Focus(FocusState.Programmatic);
        UpdatePositionFromWindow();
        _ = StartPreviewAsync();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(ScreenFaceMirrorViewModel.State)
            || args.PropertyName == nameof(ScreenFaceMirrorViewModel.IsAllTargetsSelected))
        {
            SetStateBrush();
        }

        if (args.PropertyName == nameof(ScreenFaceMirrorViewModel.State)
            || args.PropertyName == nameof(ScreenFaceMirrorViewModel.ReviewVideoUri))
        {
            UpdateReviewPlayback();
        }

        if (args.PropertyName == nameof(ScreenFaceMirrorViewModel.ScreenPreviewUri))
        {
            ScreenPreviewPlaceholder.Visibility =
                viewModel.ScreenPreviewUri is null && viewModel.State != MirrorState.Reviewing
                    ? Visibility.Visible
                    : Visibility.Collapsed;
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
        windowHandle = hwnd;
        var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
        appWindow = AppWindow.GetFromWindowId(windowId);
        appWindow.Resize(new Windows.Graphics.SizeInt32(390, 300));
        appWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        appWindow.SetPresenter(AppWindowPresenterKind.CompactOverlay);
        MoveToMirrorPosition(viewModel.MirrorPosition);
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
        viewModel.UpdateCaptureMonitor(MonitorTargetResolver.ResolveIndexForWindow(windowHandle));
    }

    private void MoveToMirrorPosition(MirrorPosition position)
    {
        if (appWindow is null)
        {
            return;
        }

        var area = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Primary);
        var workArea = area.WorkArea;
        var size = appWindow.Size;
        var left = workArea.X + (int)Math.Round(workArea.Width * position.XRatio) - size.Width / 2;
        var top = workArea.Y + (int)Math.Round(workArea.Height * position.YRatio) - size.Height / 2;
        appWindow.Move(new Windows.Graphics.PointInt32(
            ClampWindowCoordinate(left, workArea.X, workArea.X + workArea.Width - size.Width),
            ClampWindowCoordinate(top, workArea.Y, workArea.Y + workArea.Height - size.Height)));
    }

    private static int ClampWindowCoordinate(int value, int min, int max)
    {
        if (max < min)
        {
            return min;
        }

        return Math.Max(min, Math.Min(max, value));
    }

    private async Task StartPreviewAsync()
    {
        if (viewModel.State == MirrorState.Reviewing || viewModel.HasReviewedClip)
        {
            return;
        }

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
        viewModel.HandleWindowClosed();
        StopReviewPlayback();
        await StopPreviewAsync();
        viewModel.DisposePreview();
    }

    private void UpdateReviewPlayback()
    {
        if (viewModel.ReviewVideoUri is not { } uri
            || viewModel.State is not (MirrorState.Reviewing or MirrorState.Failed))
        {
            StopReviewPlayback();
            ReviewElement.Visibility = Visibility.Collapsed;
            FacePreviewBubble.Visibility = Visibility.Visible;
            if (viewModel.ScreenPreviewUri is null)
            {
                ScreenPreviewPlaceholder.Visibility = Visibility.Visible;
            }

            return;
        }

        ScreenPreviewPlaceholder.Visibility = Visibility.Collapsed;
        FacePreviewBubble.Visibility = Visibility.Collapsed;
        ReviewElement.Visibility = Visibility.Visible;
        StopReviewPlayback();
        reviewPlayer = new MediaPlayer
        {
            AutoPlay = false,
            IsMuted = true,
            Source = MediaSource.CreateFromUri(uri)
        };
        reviewPlayer.MediaEnded += HandleReviewMediaEnded;
        ReviewElement.SetMediaPlayer(reviewPlayer);
        reviewPlayer.Play();
    }

    private void StopReviewPlayback()
    {
        ReviewElement.SetMediaPlayer(null);
        if (reviewPlayer is null)
        {
            return;
        }

        reviewPlayer.MediaEnded -= HandleReviewMediaEnded;
        reviewPlayer.Dispose();
        reviewPlayer = null;
    }

    private static void HandleReviewMediaEnded(MediaPlayer sender, object args)
    {
        sender.PlaybackSession.Position = TimeSpan.Zero;
        sender.Play();
    }

    private void SetStateBrush()
    {
        var key = viewModel.State switch
        {
            MirrorState.Idle when viewModel.IsAllTargetsSelected => "PingRainbowBorderBrush",
            MirrorState.Reviewing when viewModel.IsAllTargetsSelected => "PingRainbowBorderBrush",
            MirrorState.Idle => "PingBorderIdleBrush",
            MirrorState.Reviewing => "PingBorderIdleBrush",
            MirrorState.Recording => "PingBorderRecordingBrush",
            MirrorState.Uploading => "PingRainbowBorderBrush",
            MirrorState.Failed => "PingBorderFailedBrush",
            _ => "PingBorderIdleBrush"
        };

        var thickness = (viewModel.State is MirrorState.Idle or MirrorState.Reviewing) && !viewModel.IsAllTargetsSelected ? 1 : 2;
        MirrorBorder.BorderBrush = Root.Resources[key] as Brush;
        MirrorBorder.BorderThickness = new Thickness(thickness);
    }
}
#endif
