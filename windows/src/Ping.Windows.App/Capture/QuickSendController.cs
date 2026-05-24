using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
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

public enum QuickSendOutcome
{
    RoomBlocked,
    PermissionBlocked,
    OpenedMirror,
    StartedRecording,
    Canceled,
    Failed
}

public enum QuickSendPermissionKind
{
    Camera,
    Microphone,
    ScreenCapture
}

public sealed record ScreenFaceQuickSendPreferences
{
    public static ScreenFaceQuickSendPreferences Default { get; } = new(IsEnabled: true);

    public ScreenFaceQuickSendPreferences()
        : this(IsEnabled: true)
    {
    }

    public ScreenFaceQuickSendPreferences(
        bool IsEnabled,
        bool SaveSentCopy = false,
        bool AllowsLocalSave = false,
        bool SaveReceivedCopy = true,
        bool AutoDeleteAfter30Days = false)
    {
        this.IsEnabled = IsEnabled;
        this.SaveSentCopy = SaveSentCopy;
        this.AllowsLocalSave = AllowsLocalSave;
        this.SaveReceivedCopy = SaveReceivedCopy;
        this.AutoDeleteAfter30Days = AutoDeleteAfter30Days;
    }

    public bool IsEnabled { get; init; }

    public bool SaveSentCopy { get; init; }

    public bool AllowsLocalSave { get; init; }

    public bool SaveReceivedCopy { get; init; }

    public bool AutoDeleteAfter30Days { get; init; }
}

public sealed record ScreenFaceQuickSendSettings
{
    public static ScreenFaceQuickSendSettings Default { get; } = new();

    public ScreenFaceQuickSendPreferences Preferences { get; init; } = ScreenFaceQuickSendPreferences.Default;

    public string? DefaultRoomId { get; init; }
}

public sealed class ScreenFaceQuickSendSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private readonly string path;

    public ScreenFaceQuickSendSettingsStore()
        : this(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Ping",
            "QuickSendSettings.json"))
    {
    }

    public ScreenFaceQuickSendSettingsStore(string path)
    {
        this.path = path;
    }

    public ScreenFaceQuickSendSettings Load()
    {
        try
        {
            if (!File.Exists(path))
            {
                return ScreenFaceQuickSendSettings.Default;
            }

            var settings = JsonSerializer.Deserialize<ScreenFaceQuickSendSettings>(
                File.ReadAllText(path),
                JsonOptions);
            return settings is null
                ? ScreenFaceQuickSendSettings.Default
                : settings;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return ScreenFaceQuickSendSettings.Default;
        }
    }

    public void Save(ScreenFaceQuickSendSettings settings)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(path, JsonSerializer.Serialize(settings, JsonOptions));
    }
}

public sealed record QuickSendPreconditions(
    bool IsCameraAvailable,
    bool IsMicrophoneAvailable,
    bool IsScreenCaptureAvailable)
{
    public static QuickSendPreconditions Ready() =>
        new(
            IsCameraAvailable: true,
            IsMicrophoneAvailable: true,
            IsScreenCaptureAvailable: true);
}

public sealed record QuickSendContext(
    IReadOnlyCollection<Room> Rooms,
    string SenderUid,
    string SenderNickname,
    string PartnerLabel,
    bool AllowsLocalSave,
    bool SaveSentCopy,
    MirrorPosition MirrorPosition,
    QuickSendPreconditions Preconditions,
    string? DefaultRoomId = null);

public sealed record QuickSendHudContext(
    string RoomName,
    string ModeLabel);

public interface IQuickSendPresenter
{
    IQuickSendHudSession ShowHud(QuickSendHudContext context);

    void OpenScreenFaceMirror(ScreenFaceMirrorContext context);

    void ShowRoomBlocked(string message);

    void ShowPermissionBlocked(QuickSendPermissionKind permission, string message);
}

public interface IQuickSendHudSession
{
    int MonitorIndex { get; }

    void SetRecording();

    void SetRecordingCountdown(int secondsRemaining);

    void SetUploading();

    void SetFailed(string message);

    void RequestFadeOutClose();

    void Hide();
}

public sealed class QuickSendController
{
    private static readonly TimeSpan RecordingDuration = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan HudLeadInDuration = TimeSpan.FromMilliseconds(300);

    private readonly IScreenFaceCaptureEngine captureEngine;
    private readonly Func<SendVideoInput, CancellationToken, Task> sendAsync;
    private readonly IQuickSendPresenter presenter;
    private readonly Func<ScreenFaceQuickSendPreferences> loadPreferences;
    private readonly Func<TimeSpan, CancellationToken, Task> delayAsync;
    private readonly LocalArchive? archive;

    public QuickSendController(
        IScreenFaceCaptureEngine captureEngine,
        MessageService messageService,
        IQuickSendPresenter presenter,
        ScreenFaceQuickSendPreferences preferences,
        LocalArchive? archive = null)
        : this(captureEngine, messageService.SendAsync, presenter, () => preferences, (duration, token) => Task.Delay(duration, token), archive)
    {
    }

    public QuickSendController(
        IScreenFaceCaptureEngine captureEngine,
        Func<SendVideoInput, CancellationToken, Task> sendAsync,
        IQuickSendPresenter presenter,
        Func<ScreenFaceQuickSendPreferences> loadPreferences,
        Func<TimeSpan, CancellationToken, Task>? delayAsync = null,
        LocalArchive? archive = null)
    {
        this.captureEngine = captureEngine;
        this.sendAsync = sendAsync;
        this.presenter = presenter;
        this.loadPreferences = loadPreferences;
        this.delayAsync = delayAsync ?? ((duration, token) => Task.Delay(duration, token));
        this.archive = archive;
    }

    public async Task<QuickSendOutcome> ExecuteAsync(
        QuickSendContext context,
        CancellationToken cancellationToken = default)
    {
        var room = ResolveDefaultRoom(context);
        if (room is null)
        {
            presenter.ShowRoomBlocked("Create or join a room before using screen+face quick send.");
            return QuickSendOutcome.RoomBlocked;
        }

        if (!loadPreferences().IsEnabled)
        {
            presenter.OpenScreenFaceMirror(MirrorContextFor(context, [room]));
            return QuickSendOutcome.OpenedMirror;
        }

        var blockedPermission = BlockedPermission(context.Preconditions);
        if (blockedPermission is not null)
        {
            presenter.ShowPermissionBlocked(
                blockedPermission.Value,
                PermissionBlockedMessage(blockedPermission.Value));
            return QuickSendOutcome.PermissionBlocked;
        }

        var hud = presenter.ShowHud(new QuickSendHudContext(room.Name, "화면+얼굴"));
        string? recordedPath = null;
        var uploadStarted = false;
        CancellationTokenSource? countdownCancellation = null;
        Task? countdownTask = null;

        try
        {
            await delayAsync(HudLeadInDuration, cancellationToken).ConfigureAwait(false);
            hud.SetRecording();
            countdownCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            countdownTask = RunRecordingCountdownAsync(hud, countdownCancellation.Token);
            var recording = await captureEngine.RecordAsync(RecordingDuration, hud.MonitorIndex, cancellationToken)
                .ConfigureAwait(false);
            await StopRecordingCountdownAsync(countdownCancellation, countdownTask).ConfigureAwait(false);
            countdownCancellation = null;
            countdownTask = null;
            recordedPath = recording.FilePath;
            hud.SetUploading();

            uploadStarted = true;
            await sendAsync(
                new SendVideoInput(
                    [room],
                    recordedPath,
                    context.MirrorPosition,
                    context.SenderUid,
                    context.SenderNickname,
                    CaptureMode.ScreenFace,
                    recording.AspectRatio,
                    context.AllowsLocalSave),
                CancellationToken.None).ConfigureAwait(false);
            await TrySaveSentCopyAsync(context, recordedPath, room.Name).ConfigureAwait(false);
            hud.RequestFadeOutClose();
            return QuickSendOutcome.StartedRecording;
        }
        catch (OperationCanceledException) when (!uploadStarted)
        {
            hud.Hide();
            return QuickSendOutcome.Canceled;
        }
        catch (Exception exception)
        {
            hud.SetFailed(exception.Message);
            return QuickSendOutcome.Failed;
        }
        finally
        {
            await StopRecordingCountdownAsync(countdownCancellation, countdownTask).ConfigureAwait(false);
            if (recordedPath is not null)
            {
                TryDeleteTemporaryRecording(recordedPath);
            }
        }
    }

    private async Task TrySaveSentCopyAsync(
        QuickSendContext context,
        string recordedPath,
        string roomName)
    {
        if (!context.SaveSentCopy || archive is null)
        {
            return;
        }

        try
        {
            _ = await archive.SaveSentCopyAsync(
                recordedPath,
                LocalArchiveKind.Sent,
                roomName,
                cancellationToken: CancellationToken.None).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
        }
    }

    public static Room? ResolveDefaultRoom(QuickSendContext context)
    {
        var sendableRooms = context.Rooms
            .Where(room =>
                room.Id is not null
                && room.MemberUids.Contains(context.SenderUid)
                && room.MemberUids.Count >= 2)
            .ToArray();
        if (sendableRooms.Length == 0)
        {
            return null;
        }

        if (!string.IsNullOrWhiteSpace(context.DefaultRoomId))
        {
            var defaultRoom = sendableRooms.FirstOrDefault(room =>
                string.Equals(room.Id, context.DefaultRoomId, StringComparison.Ordinal));
            if (defaultRoom is not null)
            {
                return defaultRoom;
            }
        }

        return sendableRooms
            .OrderByDescending(room => room.CreatedAt ?? DateTimeOffset.MinValue)
            .ThenBy(room => room.Name, StringComparer.OrdinalIgnoreCase)
            .First();
    }

    private static ScreenFaceMirrorContext MirrorContextFor(QuickSendContext context, IReadOnlyCollection<Room> rooms) =>
        new(
            rooms,
            context.SenderUid,
            context.SenderNickname,
            context.PartnerLabel,
            context.AllowsLocalSave,
            context.SaveSentCopy,
            InitialPosition: context.MirrorPosition);

    private static async Task RunRecordingCountdownAsync(
        IQuickSendHudSession hud,
        CancellationToken cancellationToken)
    {
        try
        {
            for (var secondsRemaining = (int)Math.Ceiling(RecordingDuration.TotalSeconds);
                 secondsRemaining > 0;
                 secondsRemaining--)
            {
                hud.SetRecordingCountdown(secondsRemaining);
                await Task.Delay(TimeSpan.FromSeconds(1), cancellationToken).ConfigureAwait(false);
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
                await task.ConfigureAwait(false);
            }
        }
        finally
        {
            cancellation.Dispose();
        }
    }

    private static QuickSendPermissionKind? BlockedPermission(QuickSendPreconditions preconditions)
    {
        if (!preconditions.IsScreenCaptureAvailable)
        {
            return QuickSendPermissionKind.ScreenCapture;
        }

        if (!preconditions.IsCameraAvailable)
        {
            return QuickSendPermissionKind.Camera;
        }

        if (!preconditions.IsMicrophoneAvailable)
        {
            return QuickSendPermissionKind.Microphone;
        }

        return null;
    }

    private static string PermissionBlockedMessage(QuickSendPermissionKind permission) => permission switch
    {
        QuickSendPermissionKind.ScreenCapture => "Screen capture permission is required for screen+face quick send.",
        QuickSendPermissionKind.Camera => "Camera permission is required for screen+face quick send.",
        QuickSendPermissionKind.Microphone => "Microphone permission is required for screen+face quick send.",
        _ => throw new ArgumentOutOfRangeException(nameof(permission), permission, "Unknown quick-send permission.")
    };

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
}

public sealed class QuickSendHudViewModel : INotifyPropertyChanged
{
    private MirrorState state = MirrorState.Idle;
    private string statusMessage = "Starting...";
    private string recordingCountdownText = "3";
    private bool isCloseRequested;
    private bool isFadeOutRequested;

    public QuickSendHudViewModel(QuickSendHudContext context)
    {
        RoomName = context.RoomName;
        ModeLabel = context.ModeLabel;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public event EventHandler? CloseRequested;

    public event EventHandler? FadeOutRequested;

    public string RoomName { get; }

    public string ModeLabel { get; }

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
            OnPropertyChanged(nameof(CanRetry));
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
        _ => throw new ArgumentOutOfRangeException(nameof(State), State, "Unknown HUD state.")
    };

    public bool CanRetry => State == MirrorState.Failed;

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

    public void SetRecording()
    {
        State = MirrorState.Recording;
        SetRecordingCountdown(3);
    }

    public void SetRecordingCountdown(int secondsRemaining)
    {
        RecordingCountdownText = Math.Max(1, secondsRemaining).ToString();
        StatusMessage = $"Recording {RecordingCountdownText}...";
    }

    public void SetUploading()
    {
        State = MirrorState.Uploading;
        StatusMessage = "Sending...";
    }

    public void SetFailed(string message)
    {
        State = MirrorState.Failed;
        StatusMessage = $"Could not send. Press Enter to retry, or Esc to close. {message}";
    }

    public void RequestFadeOutClose()
    {
        IsFadeOutRequested = true;
        FadeOutRequested?.Invoke(this, EventArgs.Empty);
        RequestClose();
    }

    public void RequestClose()
    {
        IsCloseRequested = true;
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

#if WINDOWS
public sealed partial class QuickSendHudWindow : Window, IQuickSendHudSession
{
    private readonly QuickSendHudViewModel viewModel;
    private readonly CancellationTokenSource cancellation;
    private AppWindow? appWindow;
    private IntPtr windowHandle;
    private bool shouldCloseAfterFade;
    private bool uploadStarted;
    private bool isClosed;

    public QuickSendHudWindow(QuickSendHudContext context, CancellationTokenSource cancellation)
    {
        this.cancellation = cancellation;
        viewModel = new QuickSendHudViewModel(context);
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

    public event EventHandler? RetryRequested;

    public int MonitorIndex => MonitorTargetResolver.ResolveIndexForWindow(windowHandle);

    public void SetRecording() => viewModel.SetRecording();

    public void SetRecordingCountdown(int secondsRemaining) => viewModel.SetRecordingCountdown(secondsRemaining);

    public void SetUploading()
    {
        uploadStarted = true;
        viewModel.SetUploading();
    }

    public void SetFailed(string message) => viewModel.SetFailed(message);

    public void RequestFadeOutClose() => viewModel.RequestFadeOutClose();

    public void Hide() => CloseSafely();

    private void HandleLoaded(object sender, RoutedEventArgs args)
    {
        Root.Focus(FocusState.Programmatic);
    }

    private void HandleKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == Windows.System.VirtualKey.Enter && viewModel.CanRetry)
        {
            args.Handled = true;
            RetryRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        if (args.Key != Windows.System.VirtualKey.Escape)
        {
            return;
        }

        args.Handled = true;
        CancelIfBeforeUpload();
        CloseSafely();
    }

    private void HandleViewModelPropertyChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName == nameof(QuickSendHudViewModel.State))
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

        CloseSafely();
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
        CloseSafely();
    }

    private void HandleClosed(object sender, WindowEventArgs args)
    {
        isClosed = true;
        CancelIfBeforeUpload();
    }

    private void CancelIfBeforeUpload()
    {
        if (uploadStarted || viewModel.CanRetry)
        {
            return;
        }

        try
        {
            cancellation.Cancel();
        }
        catch (ObjectDisposedException)
        {
        }
    }

    private void CloseSafely()
    {
        if (isClosed)
        {
            return;
        }

        Close();
    }

    private void ConfigureWindow()
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        windowHandle = hwnd;
        var windowId = Win32Interop.GetWindowIdFromWindow(hwnd);
        appWindow = AppWindow.GetFromWindowId(windowId);
        appWindow.Resize(new Windows.Graphics.SizeInt32(260, 116));
        appWindow.TitleBar.ExtendsContentIntoTitleBar = true;
        appWindow.SetPresenter(AppWindowPresenterKind.CompactOverlay);
    }

    private void SetStateBrush()
    {
        var key = viewModel.State switch
        {
            MirrorState.Idle => "PingBorderIdleBrush",
            MirrorState.Recording => "PingBorderRecordingBrush",
            MirrorState.Reviewing => "PingBorderIdleBrush",
            MirrorState.Uploading => "PingRainbowBorderBrush",
            MirrorState.Failed => "PingBorderFailedBrush",
            _ => "PingBorderIdleBrush"
        };

        var thickness = viewModel.State == MirrorState.Idle ? 1 : 2;
        HudBorder.BorderBrush = Root.Resources[key] as Brush;
        HudBorder.BorderThickness = new Thickness(thickness);
    }
}
#endif
