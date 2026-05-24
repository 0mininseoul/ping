using Ping.Windows.App.Capture;
using Ping.Windows.Core.Backend;
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
    public async Task EnabledQuickSend_RecordsImmediatelyAndSendsScreenFaceMessage()
    {
        SendVideoInput? sent = null;
        var controller = CreateController(sendAsync: (input, _) =>
        {
            sent = input;
            return Task.CompletedTask;
        });

        var outcome = await controller.ExecuteAsync(ContextWith());

        Assert.Equal(QuickSendOutcome.StartedRecording, outcome);
        Assert.True(controller.CaptureEngine.RecordWasCalled);
        Assert.NotNull(sent);
        Assert.Equal(CaptureMode.ScreenFace, sent!.CaptureMode);
        Assert.Equal(controller.CaptureEngine.Result.AspectRatio, sent.AspectRatio);
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
    public void FailedHudMessage_AllowsEnterRetry()
    {
        var viewModel = new QuickSendHudViewModel(new QuickSendHudContext("Main", "화면+얼굴"));

        viewModel.SetFailed("network");

        Assert.True(viewModel.CanRetry);
        Assert.Contains("Press Enter to retry", viewModel.StatusMessage, StringComparison.Ordinal);
    }

    private static TestQuickSendController CreateController(
        FakeQuickSendPresenter? presenter = null,
        ScreenFaceQuickSendPreferences? preferences = null,
        Func<SendVideoInput, CancellationToken, Task>? sendAsync = null)
    {
        var engine = new FakeScreenFaceCaptureEngine();
        var controller = new QuickSendController(
            engine,
            sendAsync ?? ((_, _) => Task.CompletedTask),
            presenter ?? new FakeQuickSendPresenter(),
            () => preferences ?? new ScreenFaceQuickSendPreferences(IsEnabled: true),
            (_, _) => Task.CompletedTask);
        return new TestQuickSendController(controller, engine);
    }

    private static QuickSendContext ContextWith(
        IReadOnlyCollection<Room>? rooms = null,
        QuickSendPreconditions? preconditions = null,
        string? defaultRoomId = null) =>
        new(
            Rooms: rooms ?? [SendableRoom()],
            SenderUid: "sender",
            SenderNickname: "Sender",
            PartnerLabel: "Receiver",
            AllowsLocalSave: false,
            SaveSentCopy: false,
            MirrorPosition: new MirrorPosition(0.5, 0.5),
            Preconditions: preconditions ?? QuickSendPreconditions.Ready(),
            DefaultRoomId: defaultRoomId);

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
    }

    private sealed class FakeScreenFaceCaptureEngine : IScreenFaceCaptureEngine
    {
        public ScreenFaceCaptureResult Result { get; } = new("screen-face.mp4", 16.0 / 9.0);

        public bool RecordWasCalled { get; private set; }

        public int? LastRecordMonitorIndex { get; private set; }

        public Task<ScreenFaceCaptureResult> RecordAsync(
            TimeSpan duration,
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            RecordWasCalled = true;
            LastRecordMonitorIndex = monitorIndex;
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

        public IQuickSendHudSession ShowHud(QuickSendHudContext context)
        {
            LastAction = QuickSendPresenterAction.Hud;
            return new FakeQuickSendHudSession(monitorIndex);
        }

        public void OpenScreenFaceMirror(ScreenFaceMirrorContext context)
        {
            LastAction = QuickSendPresenterAction.ScreenFaceMirror;
        }

        public void ShowRoomBlocked(string message)
        {
            LastAction = QuickSendPresenterAction.RoomBlocked;
        }

        public void ShowPermissionBlocked(QuickSendPermissionKind permission, string message)
        {
            LastAction = QuickSendPresenterAction.PermissionBlocked;
            BlockedPermission = permission;
        }
    }

    private sealed class FakeQuickSendHudSession(int monitorIndex) : IQuickSendHudSession
    {
        public int MonitorIndex { get; } = monitorIndex;

        public void SetRecording()
        {
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
