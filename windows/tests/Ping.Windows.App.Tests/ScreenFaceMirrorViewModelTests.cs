using Ping.Windows.App.Capture;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.LocalState;
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
        Assert.Equal(MirrorState.Reviewing, model.State);
        Assert.NotNull(model.ReviewVideoUri);
        Assert.Null(sentInput);

        await model.HandleEnterAsync();

        Assert.NotNull(sentInput);
        Assert.Equal(CaptureMode.ScreenFace, sentInput!.CaptureMode);
        Assert.Equal(new[] { "room-1" }, sentInput.Rooms.Select(room => room.Id ?? string.Empty).ToArray());
    }

    [Fact]
    public async Task Enter_UsesInitialMirrorPositionWhenWindowHasNotMoved()
    {
        SendVideoInput? sentInput = null;
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext() with
            {
                InitialPosition = new MirrorPosition(0.15, 0.75)
            },
            new FakeScreenFaceCaptureEngine(),
            (input, _) =>
            {
                sentInput = input;
                return Task.CompletedTask;
            });

        await model.HandleEnterAsync();
        await model.HandleEnterAsync();

        Assert.NotNull(sentInput);
        Assert.Equal(0.15, sentInput!.MirrorPosition.XRatio, precision: 6);
        Assert.Equal(0.75, sentInput.MirrorPosition.YRatio, precision: 6);
    }

    [Fact]
    public void UpdateMirrorPosition_SavesLatestPlacement()
    {
        MirrorPosition? saved = null;
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext() with
            {
                SaveMirrorPosition = position => saved = position
            },
            new FakeScreenFaceCaptureEngine(),
            (_, _) => Task.CompletedTask);

        model.UpdateMirrorPosition(20, 80, 100, 100);

        Assert.NotNull(saved);
        Assert.Equal(0.2, saved!.XRatio, precision: 6);
        Assert.Equal(0.8, saved.YRatio, precision: 6);
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

        Assert.Equal(MirrorState.Reviewing, model.State);
        Assert.NotNull(model.ReviewVideoUri);
    }

    [Fact]
    public async Task Enter_WhenSendFails_RetriesSameReviewedClipWithoutRecordingAgain()
    {
        var engine = new FakeScreenFaceCaptureEngine();
        var attempts = new List<SendVideoInput>();
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext(),
            engine,
            (input, _) =>
            {
                attempts.Add(input);
                if (attempts.Count == 1)
                {
                    throw new InvalidOperationException("Upload failed.");
                }

                return Task.CompletedTask;
            });

        await model.HandleEnterAsync();
        var reviewedUri = model.ReviewVideoUri;
        await model.HandleEnterAsync();

        Assert.Equal(MirrorState.Failed, model.State);
        Assert.Equal(reviewedUri, model.ReviewVideoUri);
        Assert.Equal(1, engine.RecordCount);

        await model.HandleEnterAsync();

        Assert.True(model.IsCloseRequested);
        Assert.Equal(1, engine.RecordCount);
        Assert.Equal(2, attempts.Count);
        Assert.Equal(attempts[0].LocalVideoPath, attempts[1].LocalVideoPath);
    }

    [Fact]
    public async Task FailedUpload_DoesNotSaveSentCopyBeforeUploadSucceeds()
    {
        var archive = new LocalArchive(Path.Combine(
            Path.GetTempPath(),
            "PingScreenFaceArchiveTests",
            Guid.NewGuid().ToString("N")));
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext(saveSentCopy: true),
            new FileWritingScreenFaceCaptureEngine(),
            (_, _) => throw new InvalidOperationException("Upload failed."),
            archive);

        await model.HandleEnterAsync();
        await model.HandleEnterAsync();

        Assert.Equal(MirrorState.Failed, model.State);
        AssertNoSentArchiveFiles(archive);
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
        await model.HandleEnterAsync();

        Assert.Equal(2, engine.LastPreviewMonitorIndex);
        Assert.Equal(3, engine.LastRecordMonitorIndex);
        Assert.NotNull(sentInput);
    }

    [Fact]
    public async Task LoadPreviewFailureClearsStalePreview()
    {
        var engine = new FailingAfterFirstPreviewEngine();
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext(),
            engine,
            (_, _) => Task.CompletedTask);

        await model.LoadPreviewAsync();
        var firstPreviewPath = engine.FirstPreviewPath;

        Assert.NotNull(model.ScreenPreviewUri);
        Assert.True(File.Exists(firstPreviewPath));

        await model.LoadPreviewAsync();

        Assert.Null(model.ScreenPreviewUri);
        Assert.False(File.Exists(firstPreviewPath));
        Assert.Contains("Preview unavailable", model.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public async Task WindowClosed_DeletesPreviewAndReviewedClipWithoutRequestingCloseAgain()
    {
        var engine = new FileWritingScreenFaceCaptureEngine();
        var model = new ScreenFaceMirrorViewModel(
            MultiRoomContext(),
            engine,
            (_, _) => Task.CompletedTask);
        var closeRequestCount = 0;
        model.CloseRequested += (_, _) => closeRequestCount += 1;

        await model.LoadPreviewAsync();
        var previewPath = model.ScreenPreviewUri?.LocalPath;
        await model.HandleEnterAsync();
        var reviewedPath = model.ReviewVideoUri?.LocalPath;

        Assert.NotNull(previewPath);
        Assert.NotNull(reviewedPath);
        Assert.True(File.Exists(previewPath));
        Assert.True(File.Exists(reviewedPath));

        model.HandleWindowClosed();

        Assert.True(model.IsCloseRequested);
        Assert.Null(model.ScreenPreviewUri);
        Assert.Null(model.ReviewVideoUri);
        Assert.False(File.Exists(previewPath));
        Assert.False(File.Exists(reviewedPath));
        Assert.Equal(0, closeRequestCount);
    }

    [Fact]
    public async Task EscapeAfterRecordingBeforeReview_DoesNotKeepReviewedClip()
    {
        ScreenFaceMirrorViewModel? model = null;
        var engine = new CancelingFileWritingScreenFaceCaptureEngine(() => model!.HandleEscape());
        model = new ScreenFaceMirrorViewModel(
            MultiRoomContext(),
            engine,
            (_, _) => Task.CompletedTask);

        await model.HandleEnterAsync();

        Assert.True(model.IsCloseRequested);
        Assert.Null(model.ReviewVideoUri);
        Assert.NotNull(engine.OutputPath);
        Assert.False(File.Exists(engine.OutputPath));
    }

    private static ScreenFaceMirrorContext MultiRoomContext(bool saveSentCopy = false) =>
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
            SaveSentCopy: saveSentCopy);

    private static void AssertNoSentArchiveFiles(LocalArchive archive)
    {
        var folder = archive.FolderFor(LocalArchiveKind.Sent);
        Assert.False(Directory.Exists(folder) && Directory.EnumerateFiles(folder, "*.mp4").Any());
    }

    private sealed class FakeScreenFaceCaptureEngine : IScreenFaceCaptureEngine
    {
        public int? LastRecordMonitorIndex { get; private set; }

        public int? LastPreviewMonitorIndex { get; private set; }

        public int RecordCount { get; private set; }

        public Task<ScreenFaceCaptureResult> RecordAsync(
            TimeSpan duration,
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            RecordCount++;
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

    private sealed class FileWritingScreenFaceCaptureEngine : IScreenFaceCaptureEngine
    {
        public async Task<ScreenFaceCaptureResult> RecordAsync(
            TimeSpan duration,
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            _ = duration;
            _ = monitorIndex;
            var directory = Path.Combine(
                Path.GetTempPath(),
                "PingScreenFaceWindowClosedTests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, "screen-face.mp4");
            await File.WriteAllBytesAsync(path, [0x00, 0x01], cancellationToken);
            return new ScreenFaceCaptureResult(path, 16.0 / 9.0);
        }

        public async Task<ScreenFacePreviewResult> CapturePreviewAsync(
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            _ = monitorIndex;
            var directory = Path.Combine(
                Path.GetTempPath(),
                "PingScreenFaceWindowClosedPreviewTests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, "preview.bmp");
            await File.WriteAllBytesAsync(path, [0x00, 0x01], cancellationToken);
            return new ScreenFacePreviewResult(path, 16.0 / 9.0);
        }

        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() =>
            Task.FromResult(new ScreenCaptureSelfTestResult(true, PingCaptureErrorCode.Success, "ok"));
    }

    private sealed class CancelingFileWritingScreenFaceCaptureEngine(Action beforeReturn) : IScreenFaceCaptureEngine
    {
        public string? OutputPath { get; private set; }

        public async Task<ScreenFaceCaptureResult> RecordAsync(
            TimeSpan duration,
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            _ = duration;
            _ = monitorIndex;
            var directory = Path.Combine(
                Path.GetTempPath(),
                "PingScreenFaceCancelTests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            OutputPath = Path.Combine(directory, "screen-face.mp4");
            await File.WriteAllBytesAsync(OutputPath, [0x00, 0x01], cancellationToken);
            beforeReturn();
            return new ScreenFaceCaptureResult(OutputPath, 16.0 / 9.0);
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
    }

    private sealed class FailingAfterFirstPreviewEngine : IScreenFaceCaptureEngine
    {
        private bool hasReturnedPreview;

        public string FirstPreviewPath { get; private set; } = string.Empty;

        public Task<ScreenFaceCaptureResult> RecordAsync(
            TimeSpan duration,
            int monitorIndex,
            CancellationToken cancellationToken)
        {
            _ = duration;
            _ = monitorIndex;
            _ = cancellationToken;
            return Task.FromResult(new ScreenFaceCaptureResult(
                Path.Combine(Path.GetTempPath(), "screen-face.mp4"),
                16.0 / 9.0));
        }

        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, CancellationToken cancellationToken)
        {
            _ = monitorIndex;
            _ = cancellationToken;
            if (hasReturnedPreview)
            {
                throw new InvalidOperationException("capture failed");
            }

            hasReturnedPreview = true;
            var directory = Path.Combine(
                Path.GetTempPath(),
                "PingScreenFaceMirrorPreviewTests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            FirstPreviewPath = Path.Combine(directory, "preview.bmp");
            File.WriteAllBytes(FirstPreviewPath, [0x01, 0x02]);
            return Task.FromResult(new ScreenFacePreviewResult(FirstPreviewPath, 16.0 / 9.0));
        }

        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() =>
            Task.FromResult(new ScreenCaptureSelfTestResult(true, PingCaptureErrorCode.Success, "ok"));
    }
}
