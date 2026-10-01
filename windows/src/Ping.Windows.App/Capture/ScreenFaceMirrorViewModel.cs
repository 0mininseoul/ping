using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.LocalState;
using Ping.Windows.Core.Models;

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

public sealed record ScreenMirrorCaptureSelection(int MonitorIndex, ScreenCaptureViewport Viewport);

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
    private TaskCompletionSource? operationFinished;
    public Task WaitForOperationAsync() => operationFinished?.Task ?? Task.CompletedTask;
    private MirrorState state = MirrorState.Idle;
    private string statusMessage = "Enter로 녹화하고 Esc로 닫아요.";
    private string recordingCountdownText = "3";
    private string partnerLabel;
    private Uri? screenPreviewUri;
    private string? screenPreviewPath;
    private Uri? reviewVideoUri;
    private string? reviewedPath;
    private double reviewedAspectRatio = 16.0 / 9.0;
    private MirrorPosition mirrorPosition = new(0.5, 0.5);
    private MirrorPosition preferredMirrorPosition = new(0.5, 0.5);
    private int monitorIndex;
    private ScreenCaptureViewport viewport = new();
    private long captureRevision, previewRequest;
    private bool capturePreparing;
    private bool localViewportWheel;
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
        preferredMirrorPosition = mirrorPosition;
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
            OnPropertyChanged(nameof(HintText));
            OnPropertyChanged(nameof(HintOpacity));
            OnPropertyChanged(nameof(CanRecord));
            OnPropertyChanged(nameof(CanSelectTarget));
            OnPropertyChanged(nameof(CanEditViewport));
            OnPropertyChanged(nameof(ViewportGuideOpacity));
            OnPropertyChanged(nameof(RecordingCountdownOpacity));
        }
    }

    public string StateText => State switch
    {
        MirrorState.Idle => "준비",
        MirrorState.Recording => "녹화 중",
        MirrorState.Reviewing => "확인",
        MirrorState.Uploading => "보내는 중",
        MirrorState.Failed => "다시 시도",
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
            OnPropertyChanged(nameof(HintText));
        }
    }

    public string HintText => State switch
    {
        MirrorState.Idle => "↵ 녹화 · Esc 닫기",
        MirrorState.Reviewing => "↵ 전송 · ⌫ 다시",
        MirrorState.Uploading => "보내는 중…",
        MirrorState.Failed => HasReviewedClip ? "↵ 재전송 · ⌫ 다시" : "↵ 다시 · Esc 닫기",
        MirrorState.Recording => string.Empty,
        _ => StatusMessage
    };

    public double HintOpacity => State == MirrorState.Recording ? 0 : 1;

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
    public MirrorPosition PreferredMirrorPosition => preferredMirrorPosition;

    public void UpdateMirrorPlacement(CaptureRect client, CaptureRect display, CaptureRect workArea, bool savePreference = true)
    {
        mirrorPosition = CaptureMirrorLayout.SenderPosition(client, display);
        OnPropertyChanged(nameof(MirrorPosition));
        if (!savePreference) return;
        var preference = CaptureMirrorLayout.SenderPosition(client, workArea);
        if (preferredMirrorPosition == preference) return;
        preferredMirrorPosition = preference;
        context.SaveMirrorPosition?.Invoke(preference);
    }

    public int MonitorIndex => monitorIndex;
    public ScreenCaptureViewport Viewport => viewport;
    public bool CanEditViewport => CanRecord && !IsCloseRequested && !capturePreparing;
    public double ViewportGuideOpacity => CanEditViewport ? 1 : 0;
    public string ViewportGuideText => $"{Viewport.Zoom.ToString("0.##", System.Globalization.CultureInfo.CurrentCulture)}× · {(localViewportWheel ? "창 위에서 Alt+휠" : "Alt+휠 확대")} · Alt+0 초기화";
    public ScreenMirrorCaptureSelection CaptureSelection => new(monitorIndex, viewport);

    internal void SetCapturePreparing(bool value)
    {
        if (capturePreparing == value) return;
        capturePreparing = value;
        OnPropertyChanged(nameof(CanEditViewport));
        OnPropertyChanged(nameof(ViewportGuideOpacity));
        OnPropertyChanged(nameof(CanSelectTarget));
    }

    public bool UpdateViewport(ScreenCaptureViewport selected)
    {
        ArgumentNullException.ThrowIfNull(selected);
        if (!CanEditViewport || viewport == selected) return false;
        viewport = selected;
        captureRevision++;
        OnPropertyChanged(nameof(Viewport));
        OnPropertyChanged(nameof(ViewportGuideText));
        return true;
    }

    internal void UseLocalViewportWheel()
    {
        localViewportWheel = true;
        OnPropertyChanged(nameof(ViewportGuideText));
    }

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

    public bool CanRecord => !IsCloseRequested && (State == MirrorState.Idle || (State == MirrorState.Failed && !HasReviewedClip));

    public bool CanSelectTarget => !IsCloseRequested && !capturePreparing && State is (MirrorState.Idle or MirrorState.Reviewing or MirrorState.Failed);

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
            OnPropertyChanged(nameof(CanEditViewport));
            OnPropertyChanged(nameof(ViewportGuideOpacity));
            OnPropertyChanged(nameof(CanRecord));
            OnPropertyChanged(nameof(CanSelectTarget));
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
        captureRevision++;
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
        if (!CanEditViewport) return;
        var selected = CaptureSelection;
        var revision = captureRevision;
        var request = ++previewRequest;
        string? path = null;
        bool IsCurrent() => request == previewRequest && revision == captureRevision && CanEditViewport;
        try
        {
            var preview = await captureEngine.CapturePreviewAsync(selected.MonitorIndex, selected.Viewport, cancellationToken);
            path = preview.FilePath;
            cancellationToken.ThrowIfCancellationRequested();
            if (!IsCurrent()) return;
            ClearPreview();
            screenPreviewPath = preview.FilePath;
            ScreenPreviewUri = new Uri(preview.FilePath);
            path = null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            if (!IsCurrent() || cancellationToken.IsCancellationRequested) return;
            ClearPreview();
            StatusMessage = $"Preview unavailable. Press Enter to record. {ex.Message}";
        }
        finally { if (path is not null) TryDeleteTemporaryRecording(path); }
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

    public async Task HandleEnterAsync(ScreenMirrorCaptureSelection? selection = null)
    {
        if (IsCloseRequested) return;
        if (State == MirrorState.Reviewing || (State == MirrorState.Failed && HasReviewedClip))
        {
            await UploadReviewedClipAsync();
            return;
        }

        if (!CanRecord)
        {
            return;
        }

        if (targetSelector.SelectedRooms.Count == 0)
        {
            State = MirrorState.Failed;
            StatusMessage = "No partner is ready yet. Invite someone or join a room with another member, then press Enter to retry.";
            return;
        }

        operationCancellation?.Dispose();
        operationCancellation = new CancellationTokenSource();
        operationFinished = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var cancellationToken = operationCancellation.Token;
        string? recordedPath = null;
        CancellationTokenSource? countdownCancellation = null;
        Task? countdownTask = null;
        var selected = selection ?? CaptureSelection;

        try
        {
            captureRevision++;
            State = MirrorState.Recording;
            countdownCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            countdownTask = RunRecordingCountdownAsync(countdownCancellation.Token);
            var recording = await captureEngine.RecordAsync(RecordingDuration, selected.MonitorIndex, selected.Viewport, cancellationToken);
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
            operationFinished.TrySetResult();
        }
    }

    public Task HandleRedoAsync()
    {
        if (IsCloseRequested || State != MirrorState.Reviewing && !(State == MirrorState.Failed && HasReviewedClip))
        {
            return Task.CompletedTask;
        }

        ClearReviewedClip(deleteFile: true);
        State = MirrorState.Idle;
        StatusMessage = "화면을 조정한 뒤 Enter로 다시 녹화해요.";
        return Task.CompletedTask;
    }

    private async Task UploadReviewedClipAsync()
    {
        if (reviewedPath is not { Length: > 0 } path)
        {
            return;
        }

        operationCancellation?.Dispose();
        operationCancellation = new CancellationTokenSource();
        operationFinished = new(TaskCreationOptions.RunContinuationsAsynchronously);
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
                    MirrorCoordinates.ToServicePosition(mirrorPosition),
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
            operationFinished.TrySetResult();
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
        previewRequest++;
        ClearPreview();
    }

    private void ClearPreview()
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
        StatusMessage = "Enter로 보내거나 Backspace로 다시 찍어요. Esc로 닫을 수 있어요.";
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
        OnPropertyChanged(nameof(TargetOptions));
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
