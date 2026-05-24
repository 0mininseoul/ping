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
#endif

namespace Ping.Windows.App.Capture;

public sealed record ScreenFaceMirrorContext(
    IReadOnlyCollection<Room> Rooms,
    string SenderUid,
    string SenderNickname,
    string PartnerLabel,
    bool AllowsLocalSave,
    bool SaveSentCopy,
    int MonitorIndex = MonitorTargetResolver.DefaultMonitorIndex);

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
            OnPropertyChanged(nameof(RecordingCountdownOpacity));
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

    public bool SelectNextTarget() => CanRecord && UpdateTarget(targetSelector.SelectNext());

    public bool SelectAllTargets() => CanRecord && UpdateTarget(targetSelector.SelectAll());

    public bool SelectTargetAtIndex(int index) => CanRecord && UpdateTarget(targetSelector.SelectIndex(index));

    public bool SelectTargetOption(MirrorTargetOption option) => CanRecord && UpdateTarget(targetSelector.SelectOption(option));

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
            var preview = await captureEngine.CapturePreviewAsync(monitorIndex, cancellationToken);
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
                    PartnerLabel,
                    cancellationToken: cancellationToken);
            }

            await sendAsync(
                new SendVideoInput(
                    targetSelector.SelectedRooms,
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
            await StopRecordingCountdownAsync(countdownCancellation, countdownTask);
            operationCancellation?.Dispose();
            operationCancellation = null;

            if (sent && recordedPath is not null)
            {
                TryDeleteTemporaryRecording(recordedPath);
            }
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
        if (!viewModel.CanRecord || !viewModel.HasTargetMenu)
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
        windowHandle = hwnd;
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
        viewModel.UpdateCaptureMonitor(MonitorTargetResolver.ResolveIndexForWindow(windowHandle));
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
            MirrorState.Idle when viewModel.IsAllTargetsSelected => "PingRainbowBorderBrush",
            MirrorState.Idle => "PingBorderIdleBrush",
            MirrorState.Recording => "PingBorderRecordingBrush",
            MirrorState.Uploading => "PingRainbowBorderBrush",
            MirrorState.Failed => "PingBorderFailedBrush",
            _ => "PingBorderIdleBrush"
        };

        var thickness = viewModel.State == MirrorState.Idle && !viewModel.IsAllTargetsSelected ? 1 : 2;
        MirrorBorder.BorderBrush = Root.Resources[key] as Brush;
        MirrorBorder.BorderThickness = new Thickness(thickness);
    }
}
#endif
