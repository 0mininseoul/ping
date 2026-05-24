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
using Windows.Graphics;
#endif

namespace Ping.Windows.App.Capture;

public enum MirrorState
{
    Idle,
    Recording,
    Uploading,
    Failed
}

public sealed record FaceMirrorContext(
    IReadOnlyCollection<Room> Rooms,
    string SenderUid,
    string SenderNickname,
    string PartnerLabel,
    bool AllowsLocalSave,
    bool SaveSentCopy,
    MirrorPosition? InitialPosition = null,
    Action<MirrorPosition>? SaveMirrorPosition = null);

public interface IFaceRecorder
{
    Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default);
}

public sealed record FaceRecordingResult(
    string FilePath,
    TimeSpan Duration);

public static class PingMirrorMetrics
{
    public const double Diameter = 200;
    public const double Radius = Diameter / 2;
    public const double CornerRadius = 16;
}

public sealed class FaceMirrorViewModel : INotifyPropertyChanged
{
    private static readonly TimeSpan RecordingDuration = TimeSpan.FromSeconds(3);

    private readonly FaceMirrorContext context;
    private readonly IFaceRecorder recorder;
    private readonly Func<SendVideoInput, CancellationToken, Task> sendAsync;
    private readonly LocalArchive? archive;
    private readonly MirrorTargetSelector targetSelector;
    private CancellationTokenSource? operationCancellation;
    private MirrorState state = MirrorState.Idle;
    private string statusMessage = "Press Enter to record.";
    private string recordingCountdownText = "3";
    private string partnerLabel;
    private MirrorPosition mirrorPosition = new(0.5, 0.5);
    private bool isCloseRequested;
    private bool isFadeOutRequested;

    public FaceMirrorViewModel(
        FaceMirrorContext context,
        IFaceRecorder recorder,
        MessageService messageService,
        LocalArchive? archive = null)
        : this(context, recorder, messageService.SendAsync, archive)
    {
    }

    public FaceMirrorViewModel(
        FaceMirrorContext context,
        IFaceRecorder recorder,
        Func<SendVideoInput, CancellationToken, Task> sendAsync,
        LocalArchive? archive = null)
    {
        this.context = context;
        this.recorder = recorder;
        this.sendAsync = sendAsync;
        this.archive = archive;
        targetSelector = new MirrorTargetSelector(context.Rooms, context.PartnerLabel);
        partnerLabel = targetSelector.Label;
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

    public MirrorPosition MirrorPosition => mirrorPosition;

    public IFaceRecorder Recorder => recorder;

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
            var recording = await recorder.RecordAsync(RecordingDuration, cancellationToken);
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
                    CaptureMode.FaceOnly,
                    AspectRatio: 1,
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
public sealed partial class FaceMirrorWindow : Window
{
    private readonly FaceMirrorViewModel viewModel;
    private readonly FaceRecorder? previewRecorder;
    private AppWindow? appWindow;
    private bool shouldCloseAfterFade;

    public FaceMirrorWindow(FaceMirrorViewModel viewModel)
    {
        this.viewModel = viewModel;
        previewRecorder = viewModel.Recorder as FaceRecorder;
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
            await viewModel.HandleEnterAsync();
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

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(FaceMirrorViewModel.State)
            || args.PropertyName == nameof(FaceMirrorViewModel.IsAllTargetsSelected))
        {
            SetStateBrush();
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
        appWindow.Resize(new Windows.Graphics.SizeInt32(260, 270));
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

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        Root.Focus(FocusState.Programmatic);
        UpdatePositionFromWindow();
        if (previewRecorder is null)
        {
            return;
        }

        try
        {
            await previewRecorder.StartPreviewAsync(PreviewElement);
            PreviewPlaceholder.Visibility = Visibility.Collapsed;
        }
        catch (Exception)
        {
            PreviewPlaceholder.Visibility = Visibility.Visible;
        }
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

    private async void HandleClosed(object sender, WindowEventArgs args)
    {
        if (previewRecorder is not null)
        {
            await previewRecorder.StopPreviewAsync(PreviewElement);
        }
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
