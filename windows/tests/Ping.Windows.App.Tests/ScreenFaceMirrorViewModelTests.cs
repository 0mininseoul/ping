using Ping.Windows.App.Capture;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class ScreenFaceMirrorViewModelTests
{
    [Fact]
    public async Task TargetShortcuts_SelectSingleRoomBeforeSendingScreenFaceMessage()
    {
        SendVideoInput? sentInput = null;
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext(),
            new FakeScreenFaceCaptureEngine(),
            (input, _) =>
            {
                sentInput = input;
                return Task.CompletedTask;
            });

        Assert.Equal("All rooms", model.PartnerLabel);
        Assert.True(model.IsAllTargetsSelected);
        Assert.True(model.SelectNextTarget());
        Assert.Equal("Main", model.PartnerLabel);
        Assert.False(model.IsAllTargetsSelected);

        await model.HandleEnterAsync();

        Assert.NotNull(sentInput);
        Assert.Equal(CaptureMode.ScreenFace, sentInput!.CaptureMode);
        Assert.Equal(new[] { "room-1" }, sentInput.Rooms.Select(room => room.Id ?? string.Empty).ToArray());
    }

    [Fact]
    public async Task Enter_ShowsRecordingCountdownWhileCaptureRuns()
    {
        var engine = new BlockingScreenFaceCaptureEngine();
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext(),
            engine,
            (_, _) => Task.CompletedTask);

        var recordingTask = model.HandleEnterAsync();
        await engine.RecordStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));

        Assert.Equal(MirrorState.Recording, model.State);
        Assert.Equal("3", model.RecordingCountdownText);
        Assert.Equal(1, model.RecordingCountdownOpacity);
        Assert.Contains("Recording 3", model.StatusMessage, StringComparison.Ordinal);

        engine.Complete();
        await recordingTask;
    }

    [Fact]
    public void TargetMenuOptions_MatchScreenFaceRooms()
    {
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext(),
            new FakeScreenFaceCaptureEngine(),
            (_, _) => Task.CompletedTask);

        Assert.True(model.HasTargetMenu);
        Assert.Collection(
            model.TargetOptions,
            option => Assert.True(option.IsAll),
            option => Assert.Equal("Main", option.Label),
            option => Assert.Equal("Design", option.Label));

        Assert.True(model.SelectTargetOption(model.TargetOptions[2]));
        Assert.Equal("Design", model.PartnerLabel);
    }

    [Fact]
    public async Task Capture_UsesConfiguredMonitorIndex()
    {
        SendVideoInput? sentInput = null;
        var engine = new FakeScreenFaceCaptureEngine();
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext() with { MonitorIndex = 2 },
            engine,
            (input, _) =>
            {
                sentInput = input;
                return Task.CompletedTask;
            });

        await model.LoadPreviewAsync();
        model.UpdateCaptureMonitor(3);
        await model.HandleEnterAsync();

        Assert.Equal(2, engine.LastPreviewMonitorIndex);
        Assert.Equal(3, engine.LastRecordMonitorIndex);
        Assert.NotNull(sentInput);
    }

    private static ScreenFaceMirrorContext MultiRoomContext() =>
        new(
            Rooms:
            [
                new Room(
                    Id: "room-1",
                    Name: "Main",
                    SearchableName: "main",
                    OwnerUid: "sender",
                    MemberUids: ["sender", "receiver-1"],
                    MemberNicknames: new Dictionary<string, string>
                    {
                        ["sender"] = "Sender",
                        ["receiver-1"] = "Receiver 1"
                    },
                    Status: RoomStatus.Full),
                new Room(
                    Id: "room-2",
                    Name: "Design",
                    SearchableName: "design",
                    OwnerUid: "receiver-2",
                    MemberUids: ["sender", "receiver-2"],
                    MemberNicknames: new Dictionary<string, string>
                    {
                        ["sender"] = "Sender",
                        ["receiver-2"] = "Receiver 2"
                    },
                    Status: RoomStatus.Full)
            ],
            SenderUid: "sender",
            SenderNickname: "Sender",
            PartnerLabel: "All rooms",
            AllowsLocalSave: true,
            SaveSentCopy: false);

    private sealed class FakeScreenFaceCaptureEngine : IScreenFaceCaptureEngine
    {
        public int? LastRecordMonitorIndex { get; private set; }

        public int? LastPreviewMonitorIndex { get; private set; }

        public Task<ScreenFaceCaptureResult> RecordAsync(
            TimeSpan duration,
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            LastRecordMonitorIndex = monitorIndex;
            var uniquePath = Path.Combine(
                Path.GetTempPath(),
                "PingScreenFaceMirrorTests",
                Guid.NewGuid().ToString("N"),
                "screen-face.mp4");
            return Task.FromResult(new ScreenFaceCaptureResult(uniquePath, 16.0 / 9.0));
        }

        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, CancellationToken cancellationToken)
        {
            LastPreviewMonitorIndex = monitorIndex;
            return Task.FromResult(new ScreenFacePreviewResult(
                Path.Combine(Path.GetTempPath(), "preview.bmp"),
                16.0 / 9.0));
        }

        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() =>
            Task.FromResult(new ScreenCaptureSelfTestResult(true, PingCaptureErrorCode.Success, "ok"));
    }

    private sealed class BlockingScreenFaceCaptureEngine : IScreenFaceCaptureEngine
    {
        private readonly TaskCompletionSource<ScreenFaceCaptureResult> recording = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource RecordStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public Task<ScreenFaceCaptureResult> RecordAsync(
            TimeSpan duration,
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            _ = duration;
            _ = monitorIndex;
            _ = cancellationToken;
            RecordStarted.SetResult();
            return recording.Task;
        }

        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, CancellationToken cancellationToken)
        {
            _ = monitorIndex;
            _ = cancellationToken;
            return Task.FromResult(new ScreenFacePreviewResult(
                Path.Combine(Path.GetTempPath(), "preview.bmp"),
                16.0 / 9.0));
        }

        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() =>
            Task.FromResult(new ScreenCaptureSelfTestResult(true, PingCaptureErrorCode.Success, "ok"));

        public void Complete()
        {
            var uniquePath = Path.Combine(
                Path.GetTempPath(),
                "PingScreenFaceMirrorTests",
                Guid.NewGuid().ToString("N"),
                "screen-face.mp4");
            recording.SetResult(new ScreenFaceCaptureResult(uniquePath, 16.0 / 9.0));
        }
    }
}
