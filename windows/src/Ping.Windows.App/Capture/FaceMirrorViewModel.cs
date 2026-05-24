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
    bool SaveSentCopy);

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
    private CancellationTokenSource? operationCancellation;
    private MirrorState state = MirrorState.Idle;
    private string statusMessage = "Press Enter to record.";
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
            StatusMessage = "Recording...";
            var recording = await recorder.RecordAsync(RecordingDuration, cancellationToken);
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

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(FaceMirrorViewModel.State))
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
