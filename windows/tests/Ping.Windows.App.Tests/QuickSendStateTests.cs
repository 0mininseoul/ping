using Ping.Windows.App.Capture;
using Ping.Windows.App.Onboarding;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.LocalState;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class QuickSendStateTests
{
    [Fact]
    public async Task NoRoom_OpensRoomManagerBlockedState()
    {
        var presenter = new FakeQuickSendPresenter();
        var controller = CreateController(presenter: presenter);

        var outcome = await controller.ExecuteAsync(ContextWith(rooms: []));

        Assert.Equal(QuickSendOutcome.RoomBlocked, outcome);
        Assert.Equal(QuickSendPresenterAction.RoomBlocked, presenter.LastAction);
        Assert.False(controller.CaptureEngine.RecordWasCalled);
    }

    [Fact]
    public async Task MissingScreenPermission_OpensOnboardingPermissionBlockedState()
    {
        var presenter = new FakeQuickSendPresenter();
        var controller = CreateController(presenter: presenter);
        var context = ContextWith(preconditions: QuickSendPreconditions.Ready() with
        {
            IsScreenCaptureAvailable = false
        });

        var outcome = await controller.ExecuteAsync(context);

        Assert.Equal(QuickSendOutcome.PermissionBlocked, outcome);
        Assert.Equal(QuickSendPresenterAction.PermissionBlocked, presenter.LastAction);
        Assert.Equal(QuickSendPermissionKind.ScreenCapture, presenter.BlockedPermission);
        Assert.False(controller.CaptureEngine.RecordWasCalled);
    }

    [Fact]
    public async Task UnsupportedWindows_BlocksQuickSendBeforePermissionMessages()
    {
        var presenter = new FakeQuickSendPresenter();
        var controller = CreateController(presenter: presenter);
        var context = ContextWith(preconditions: QuickSendPreconditions.Ready() with
        {
            WindowsStatus = WindowsSupportStatus.UnsupportedOldWindows11
        });

        var outcome = await controller.ExecuteAsync(context);

        Assert.Equal(QuickSendOutcome.PermissionBlocked, outcome);
        Assert.Equal(QuickSendPresenterAction.PermissionBlocked, presenter.LastAction);
        Assert.Equal(QuickSendPermissionKind.WindowsVersion, presenter.BlockedPermission);
        Assert.Contains("Windows 11 24H2", presenter.BlockedMessage, StringComparison.Ordinal);
        Assert.False(controller.CaptureEngine.RecordWasCalled);
    }

    [Fact]
    public async Task EnabledQuickSend_RecordsImmediatelyAndSendsScreenFaceMessage()
    {
        SendVideoInput? sent = null;
        var controller = CreateController(sendAsync: (input, _) =>
        {
            sent = input;
            return Task.CompletedTask;
        });

        var outcome = await controller.ExecuteAsync(ContextWith(
            mirrorPosition: new MirrorPosition(0.2, 0.8)));

        Assert.Equal(QuickSendOutcome.StartedRecording, outcome);
        Assert.True(controller.CaptureEngine.RecordWasCalled);
        Assert.NotNull(sent);
        Assert.Equal(CaptureMode.ScreenFace, sent!.CaptureMode);
        Assert.Equal(controller.CaptureEngine.Result.AspectRatio, sent.AspectRatio);
        Assert.Equal(0.2, sent.MirrorPosition.XRatio, precision: 6);
        Assert.Equal(0.8, sent.MirrorPosition.YRatio, precision: 6);
    }

    [Fact]
    public async Task DefaultRoomId_SelectsPreferredSendableRoom()
    {
        SendVideoInput? sent = null;
        var controller = CreateController(sendAsync: (input, _) =>
        {
            sent = input;
            return Task.CompletedTask;
        });
        var preferred = SendableRoom("room-preferred", "Preferred", DateTimeOffset.UtcNow.AddDays(-1));
        var newest = SendableRoom("room-newest", "Newest", DateTimeOffset.UtcNow);

        var outcome = await controller.ExecuteAsync(ContextWith(
            rooms: [newest, preferred],
            defaultRoomId: "room-preferred"));

        Assert.Equal(QuickSendOutcome.StartedRecording, outcome);
        Assert.Equal("room-preferred", sent?.Rooms.Single().Id);
    }

    [Fact]
    public async Task EnabledQuickSend_UsesHudMonitorIndexForCapture()
    {
        var presenter = new FakeQuickSendPresenter(monitorIndex: 2);
        var controller = CreateController(presenter: presenter);

        await controller.ExecuteAsync(ContextWith());

        Assert.Equal(2, controller.CaptureEngine.LastRecordMonitorIndex);
    }

    [Fact]
    public async Task DisabledQuickSend_OpensScreenFaceMirrorInsteadOfRecording()
    {
        var presenter = new FakeQuickSendPresenter();
        var controller = CreateController(
            presenter: presenter,
            preferences: new ScreenFaceQuickSendPreferences(IsEnabled: false));

        var outcome = await controller.ExecuteAsync(ContextWith(
            preconditions: QuickSendPreconditions.Ready() with
            {
                IsScreenCaptureAvailable = false
            }));

        Assert.Equal(QuickSendOutcome.OpenedMirror, outcome);
        Assert.Equal(QuickSendPresenterAction.ScreenFaceMirror, presenter.LastAction);
        Assert.False(controller.CaptureEngine.RecordWasCalled);
    }

    [Fact]
    public async Task DisabledQuickSend_OpensScreenFaceMirrorAtContextPosition()
    {
        var presenter = new FakeQuickSendPresenter();
        var controller = CreateController(
            presenter: presenter,
            preferences: new ScreenFaceQuickSendPreferences(IsEnabled: false));

        var outcome = await controller.ExecuteAsync(ContextWith(
            mirrorPosition: new MirrorPosition(0.25, 0.75)));

        Assert.Equal(QuickSendOutcome.OpenedMirror, outcome);
        Assert.NotNull(presenter.OpenedMirrorContext?.InitialPosition);
        Assert.Equal(0.25, presenter.OpenedMirrorContext!.InitialPosition!.XRatio, precision: 6);
        Assert.Equal(0.75, presenter.OpenedMirrorContext.InitialPosition.YRatio, precision: 6);
    }

    [Fact]
    public void FailedHudMessage_AllowsEnterRetry()
    {
        var viewModel = new QuickSendHudViewModel(new QuickSendHudContext("Main", "화면+얼굴"));

        viewModel.SetFailed("network");

        Assert.True(viewModel.CanRetry);
        Assert.Contains("Press Enter to retry", viewModel.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void RecordingHudMessage_ShowsCountdown()
    {
        var viewModel = new QuickSendHudViewModel(new QuickSendHudContext("Main", "화면+얼굴"));

        viewModel.SetRecording();
        viewModel.SetRecordingCountdown(2);

        Assert.Equal(MirrorState.Recording, viewModel.State);
        Assert.Equal("2", viewModel.RecordingCountdownText);
        Assert.Equal(1, viewModel.RecordingCountdownOpacity);
        Assert.Equal("Recording 2...", viewModel.StatusMessage);
    }

    [Fact]
    public async Task FailedQuickSend_DeletesTemporaryRecording()
    {
        var tempPath = Path.Combine(Path.GetTempPath(), "PingWindowsTests", $"{Guid.NewGuid():N}.mp4");
        Directory.CreateDirectory(Path.GetDirectoryName(tempPath)!);
        await File.WriteAllBytesAsync(tempPath, [0x00, 0x01]);
        var engine = new FakeScreenFaceCaptureEngine(new ScreenFaceCaptureResult(tempPath, 16.0 / 9.0));
        var controller = CreateController(
            engine: engine,
            sendAsync: (_, _) => throw new HttpRequestException("offline"));

        var outcome = await controller.ExecuteAsync(ContextWith());

        Assert.Equal(QuickSendOutcome.Failed, outcome);
        Assert.False(File.Exists(tempPath));
    }

    [Fact]
    public async Task CanceledAfterRecordingBeforeUpload_DoesNotSend()
    {
        var tempPath = Path.Combine(Path.GetTempPath(), "PingWindowsTests", $"{Guid.NewGuid():N}.mp4");
        Directory.CreateDirectory(Path.GetDirectoryName(tempPath)!);
        await File.WriteAllBytesAsync(tempPath, [0x00, 0x01]);
        using var cancellation = new CancellationTokenSource();
        SendVideoInput? sent = null;
        var engine = new FakeScreenFaceCaptureEngine(
            new ScreenFaceCaptureResult(tempPath, 16.0 / 9.0),
            _ => cancellation.Cancel());
        var controller = CreateController(
            engine: engine,
            sendAsync: (input, _) =>
            {
                sent = input;
                return Task.CompletedTask;
            });

        var outcome = await controller.ExecuteAsync(ContextWith(), cancellation.Token);

        Assert.Equal(QuickSendOutcome.Canceled, outcome);
        Assert.Null(sent);
        Assert.False(File.Exists(tempPath));
    }

    [Fact]
    public async Task FailedQuickSend_DoesNotSaveSentCopyBeforeUploadSucceeds()
    {
        var archive = new LocalArchive(Path.Combine(
            Path.GetTempPath(),
            "PingQuickSendArchiveTests",
            Guid.NewGuid().ToString("N")));
        var tempPath = Path.Combine(Path.GetTempPath(), "PingWindowsTests", $"{Guid.NewGuid():N}.mp4");
        Directory.CreateDirectory(Path.GetDirectoryName(tempPath)!);
        await File.WriteAllBytesAsync(tempPath, [0x00, 0x01]);
        var controller = CreateController(
            archive: archive,
            engine: new FakeScreenFaceCaptureEngine(new ScreenFaceCaptureResult(tempPath, 16.0 / 9.0)),
            sendAsync: (_, _) => throw new HttpRequestException("offline"));

        var outcome = await controller.ExecuteAsync(ContextWith(saveSentCopy: true));

        Assert.Equal(QuickSendOutcome.Failed, outcome);
        AssertNoSentArchiveFiles(archive);
    }

    private static TestQuickSendController CreateController(
        FakeQuickSendPresenter? presenter = null,
        ScreenFaceQuickSendPreferences? preferences = null,
        Func<SendVideoInput, CancellationToken, Task>? sendAsync = null,
        FakeScreenFaceCaptureEngine? engine = null,
        LocalArchive? archive = null)
    {
        engine ??= new FakeScreenFaceCaptureEngine();
        var controller = new QuickSendController(
            engine,
            sendAsync ?? ((_, _) => Task.CompletedTask),
            presenter ?? new FakeQuickSendPresenter(),
            () => preferences ?? new ScreenFaceQuickSendPreferences(IsEnabled: true),
            (_, _) => Task.CompletedTask,
            archive);
        return new TestQuickSendController(controller, engine);
    }

    private static QuickSendContext ContextWith(
        IReadOnlyCollection<Room>? rooms = null,
        QuickSendPreconditions? preconditions = null,
        string? defaultRoomId = null,
        MirrorPosition? mirrorPosition = null,
        bool saveSentCopy = false) =>
        new(
            Rooms: rooms ?? [SendableRoom()],
            SenderUid: "sender",
            SenderNickname: "Sender",
            PartnerLabel: "Receiver",
            AllowsLocalSave: false,
            SaveSentCopy: saveSentCopy,
            MirrorPosition: mirrorPosition ?? new MirrorPosition(0.5, 0.5),
            Preconditions: preconditions ?? QuickSendPreconditions.Ready(),
            DefaultRoomId: defaultRoomId);

    private static void AssertNoSentArchiveFiles(LocalArchive archive)
    {
        var folder = archive.FolderFor(LocalArchiveKind.Sent);
        Assert.False(Directory.Exists(folder) && Directory.EnumerateFiles(folder, "*.mp4").Any());
    }

    private static Room SendableRoom(
        string id = "room-1",
        string name = "Main",
        DateTimeOffset? createdAt = null) =>
        new(
            Id: id,
            Name: name,
            SearchableName: name.ToLowerInvariant(),
            OwnerUid: "sender",
            MemberUids: ["sender", "receiver"],
            MemberNicknames: new Dictionary<string, string>
            {
                ["sender"] = "Sender",
                ["receiver"] = "Receiver"
            },
            Status: RoomStatus.Open,
            CreatedAt: createdAt);

    private sealed record TestQuickSendController(
        QuickSendController Controller,
        FakeScreenFaceCaptureEngine CaptureEngine)
    {
        public Task<QuickSendOutcome> ExecuteAsync(QuickSendContext context) =>
            Controller.ExecuteAsync(context);

        public Task<QuickSendOutcome> ExecuteAsync(QuickSendContext context, CancellationToken cancellationToken) =>
            Controller.ExecuteAsync(context, cancellationToken);
    }

    private sealed class FakeScreenFaceCaptureEngine : IScreenFaceCaptureEngine
    {
        private readonly Action<CancellationToken>? beforeRecordReturns;

        public FakeScreenFaceCaptureEngine()
            : this(new ScreenFaceCaptureResult("screen-face.mp4", 16.0 / 9.0))
        {
        }

        public FakeScreenFaceCaptureEngine(
            ScreenFaceCaptureResult result,
            Action<CancellationToken>? beforeRecordReturns = null)
        {
            Result = result;
            this.beforeRecordReturns = beforeRecordReturns;
        }

        public ScreenFaceCaptureResult Result { get; }

        public bool RecordWasCalled { get; private set; }

        public int? LastRecordMonitorIndex { get; private set; }

        public Task<ScreenFaceCaptureResult> RecordAsync(
            TimeSpan duration,
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            RecordWasCalled = true;
            LastRecordMonitorIndex = monitorIndex;
            beforeRecordReturns?.Invoke(cancellationToken);
            return Task.FromResult(Result);
        }

        public Task<ScreenFacePreviewResult> CapturePreviewAsync(
            int monitorIndex,
            CancellationToken cancellationToken) =>
            Task.FromResult(new ScreenFacePreviewResult("preview.bmp", 16.0 / 9.0));

        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() =>
            Task.FromResult(new ScreenCaptureSelfTestResult(true, PingCaptureErrorCode.Success, "OK"));
    }

    private enum QuickSendPresenterAction
    {
        None,
        RoomBlocked,
        PermissionBlocked,
        ScreenFaceMirror,
        Hud
    }

    private sealed class FakeQuickSendPresenter(int monitorIndex = MonitorTargetResolver.DefaultMonitorIndex) : IQuickSendPresenter
    {
        public QuickSendPresenterAction LastAction { get; private set; }

        public QuickSendPermissionKind? BlockedPermission { get; private set; }

        public string? BlockedMessage { get; private set; }

        public ScreenFaceMirrorContext? OpenedMirrorContext { get; private set; }

        public IQuickSendHudSession ShowHud(QuickSendHudContext context)
        {
            LastAction = QuickSendPresenterAction.Hud;
            return new FakeQuickSendHudSession(monitorIndex);
        }

        public void OpenScreenFaceMirror(ScreenFaceMirrorContext context)
        {
            LastAction = QuickSendPresenterAction.ScreenFaceMirror;
            OpenedMirrorContext = context;
        }

        public void ShowRoomBlocked(string message)
        {
            BlockedMessage = message;
            LastAction = QuickSendPresenterAction.RoomBlocked;
        }

        public void ShowPermissionBlocked(QuickSendPermissionKind permission, string message)
        {
            LastAction = QuickSendPresenterAction.PermissionBlocked;
            BlockedPermission = permission;
            BlockedMessage = message;
        }
    }

    private sealed class FakeQuickSendHudSession(int monitorIndex) : IQuickSendHudSession
    {
        public int MonitorIndex { get; } = monitorIndex;

        public void SetRecording()
        {
        }

        public void SetRecordingCountdown(int secondsRemaining)
        {
            _ = secondsRemaining;
        }

        public void SetUploading()
        {
        }

        public void SetFailed(string message)
        {
        }

        public void RequestFadeOutClose()
        {
        }

        public void Hide()
        {
        }
    }
}
