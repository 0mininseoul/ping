using Ping.Windows.App.Capture;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.LocalState;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class FaceMirrorViewModelTests
{
    [Fact]
    public async Task Enter_FromIdle_RecordsAndSendsFaceOnlyMessageThenRequestsClose()
    {
        SendVideoInput? sentInput = null;
        var recorder = new FakeFaceRecorder();
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false),
            recorder,
            (input, _) =>
            {
                sentInput = input;
                return Task.CompletedTask;
            });
        recorder.StateReader = () => model.State;
        model.UpdateMirrorPosition(125, 175, 500, 700);
        var closeRequested = false;
        model.CloseRequested += (_, _) => closeRequested = true;

        await model.HandleEnterAsync();

        Assert.Equal(MirrorState.Recording, recorder.StateAtRecordStart);
        Assert.Equal(MirrorState.Reviewing, model.State);
        Assert.NotNull(model.ReviewVideoUri);
        Assert.Null(sentInput);
        Assert.False(model.IsCloseRequested);

        await model.HandleEnterAsync();

        Assert.NotNull(sentInput);
        var input = sentInput!;
        Assert.Equal(CaptureMode.FaceOnly, input.CaptureMode);
        Assert.Equal(1.0, input.AspectRatio);
        Assert.Equal(0.25, input.MirrorPosition.XRatio, precision: 6);
        Assert.Equal(0.25, input.MirrorPosition.YRatio, precision: 6);
        Assert.True(model.IsCloseRequested);
        Assert.True(closeRequested);
    }

    [Fact]
    public async Task Enter_UsesInitialMirrorPositionWhenWindowHasNotMoved()
    {
        SendVideoInput? sentInput = null;
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false) with
            {
                InitialPosition = new MirrorPosition(0.8, 0.2)
            },
            new FakeFaceRecorder(),
            (input, _) =>
            {
                sentInput = input;
                return Task.CompletedTask;
            });

        await model.HandleEnterAsync();
        await model.HandleEnterAsync();

        Assert.NotNull(sentInput);
        Assert.Equal(0.8, sentInput!.MirrorPosition.XRatio, precision: 6);
        Assert.Equal(0.2, sentInput.MirrorPosition.YRatio, precision: 6);
    }

    [Fact]
    public void UpdateMirrorPosition_SavesLatestPlacement()
    {
        MirrorPosition? saved = null;
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false) with
            {
                SaveMirrorPosition = position => saved = position
            },
            new FakeFaceRecorder(),
            (_, _) => Task.CompletedTask);

        model.UpdateMirrorPosition(80, 20, 100, 100);

        Assert.NotNull(saved);
        Assert.Equal(0.8, saved!.XRatio, precision: 6);
        Assert.Equal(0.2, saved.YRatio, precision: 6);
    }

    [Fact]
    public async Task Enter_ShowsRecordingCountdownWhileRecorderRuns()
    {
        var recorder = new BlockingFaceRecorder();
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false),
            recorder,
            (_, _) => Task.CompletedTask);

        var recordingTask = model.HandleEnterAsync();
        await recorder.RecordStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));

        Assert.Equal(MirrorState.Recording, model.State);
        Assert.Equal("3", model.RecordingCountdownText);
        Assert.Equal(1, model.RecordingCountdownOpacity);
        Assert.Contains("Recording 3", model.StatusMessage, StringComparison.Ordinal);

        recorder.Complete();
        await recordingTask;

        Assert.Equal(MirrorState.Reviewing, model.State);
        Assert.NotNull(model.ReviewVideoUri);
    }

    [Fact]
    public async Task Enter_WhenSendFails_KeepsFailedStateWithRetryMessage()
    {
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false),
            new FakeFaceRecorder(),
            (_, _) => throw new InvalidOperationException("Upload failed."));

        await model.HandleEnterAsync();
        await model.HandleEnterAsync();

        Assert.Equal(MirrorState.Failed, model.State);
        Assert.Contains("Upload failed", model.StatusMessage, StringComparison.OrdinalIgnoreCase);
        Assert.False(model.IsCloseRequested);
    }

    [Fact]
    public async Task FailedUpload_DoesNotSaveSentCopyBeforeUploadSucceeds()
    {
        var archive = new LocalArchive(Path.Combine(
            Path.GetTempPath(),
            "PingFaceArchiveTests",
            Guid.NewGuid().ToString("N")));
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: true),
            new FileWritingFaceRecorder(),
            (_, _) => throw new InvalidOperationException("Upload failed."),
            archive);

        await model.HandleEnterAsync();
        await model.HandleEnterAsync();

        Assert.Equal(MirrorState.Failed, model.State);
        AssertNoSentArchiveFiles(archive);
    }

    [Fact]
    public async Task Enter_WhenSendFails_RetriesSameReviewedClipWithoutRecordingAgain()
    {
        var recorder = new FakeFaceRecorder();
        var attempts = new List<SendVideoInput>();
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false),
            recorder,
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
        Assert.Equal(1, recorder.RecordCount);

        await model.HandleEnterAsync();

        Assert.True(model.IsCloseRequested);
        Assert.Equal(1, recorder.RecordCount);
        Assert.Equal(2, attempts.Count);
        Assert.Equal(attempts[0].LocalVideoPath, attempts[1].LocalVideoPath);
    }

    [Fact]
    public async Task WindowClosed_DeletesReviewedClipWithoutRequestingCloseAgain()
    {
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false),
            new FileWritingFaceRecorder(),
            (_, _) => Task.CompletedTask);
        var closeRequestCount = 0;
        model.CloseRequested += (_, _) => closeRequestCount += 1;

        await model.HandleEnterAsync();
        var reviewedPath = model.ReviewVideoUri?.LocalPath;

        Assert.NotNull(reviewedPath);
        Assert.True(File.Exists(reviewedPath));

        model.HandleWindowClosed();

        Assert.True(model.IsCloseRequested);
        Assert.Null(model.ReviewVideoUri);
        Assert.False(File.Exists(reviewedPath));
        Assert.Equal(0, closeRequestCount);
    }

    [Fact]
    public async Task EscapeAfterRecordingBeforeReview_DoesNotKeepReviewedClip()
    {
        FaceMirrorViewModel? model = null;
        var recorder = new CancelingFileWritingFaceRecorder(() => model!.HandleEscape());
        model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false),
            recorder,
            (_, _) => Task.CompletedTask);

        await model.HandleEnterAsync();

        Assert.True(model.IsCloseRequested);
        Assert.Null(model.ReviewVideoUri);
        Assert.NotNull(recorder.OutputPath);
        Assert.False(File.Exists(recorder.OutputPath));
    }

    [Fact]
    public async Task TargetShortcuts_SelectSingleRoomOrAllRoomsBeforeSending()
    {
        SendVideoInput? sentInput = null;
        var model = new FaceMirrorViewModel(
            MultiRoomFaceMirrorContext(),
            new FakeFaceRecorder(),
            (input, _) =>
            {
                sentInput = input;
                return Task.CompletedTask;
            });

        Assert.Equal("All rooms", model.PartnerLabel);
        Assert.True(model.SelectTargetAtIndex(1));
        Assert.Equal("Design", model.PartnerLabel);

        await model.HandleEnterAsync();
        Assert.Equal(MirrorState.Reviewing, model.State);
        Assert.True(model.SelectAllTargets());
        Assert.True(model.IsAllTargetsSelected);
        Assert.True(model.SelectTargetAtIndex(1));
        await model.HandleEnterAsync();

        Assert.NotNull(sentInput);
        Assert.Equal(new[] { "room-2" }, sentInput!.Rooms.Select(room => room.Id ?? string.Empty).ToArray());
    }

    [Fact]
    public void TargetShortcuts_CycleBetweenRoomsAndAllRooms()
    {
        var model = new FaceMirrorViewModel(
            MultiRoomFaceMirrorContext(),
            new FakeFaceRecorder(),
            (_, _) => Task.CompletedTask);

        Assert.Equal("All rooms", model.PartnerLabel);
        Assert.True(model.IsAllTargetsSelected);
        Assert.True(model.SelectNextTarget());
        Assert.Equal("Main", model.PartnerLabel);
        Assert.False(model.IsAllTargetsSelected);
        Assert.True(model.SelectNextTarget());
        Assert.Equal("Design", model.PartnerLabel);
        Assert.True(model.SelectNextTarget());
        Assert.Equal("All rooms", model.PartnerLabel);
        Assert.True(model.IsAllTargetsSelected);
        Assert.True(model.SelectTargetAtIndex(0));
        Assert.False(model.IsAllTargetsSelected);
        Assert.True(model.SelectAllTargets());
        Assert.Equal("All rooms", model.PartnerLabel);
        Assert.True(model.IsAllTargetsSelected);
    }

    [Fact]
    public void TargetMenuOptions_SelectAllOrSingleRoom()
    {
        var model = new FaceMirrorViewModel(
            MultiRoomFaceMirrorContext(),
            new FakeFaceRecorder(),
            (_, _) => Task.CompletedTask);

        Assert.True(model.HasTargetMenu);
        Assert.Collection(
            model.TargetOptions,
            option =>
            {
                Assert.True(option.IsAll);
                Assert.Equal("All rooms", option.Label);
            },
            option =>
            {
                Assert.False(option.IsAll);
                Assert.Equal("Main", option.Label);
            },
            option =>
            {
                Assert.False(option.IsAll);
                Assert.Equal("Design", option.Label);
            });

        Assert.True(model.SelectTargetOption(model.TargetOptions[2]));
        Assert.Equal("Design", model.PartnerLabel);
        Assert.False(model.IsAllTargetsSelected);
        Assert.True(model.SelectTargetOption(model.TargetOptions[0]));
        Assert.Equal("All rooms", model.PartnerLabel);
        Assert.True(model.IsAllTargetsSelected);
    }

    private static FaceMirrorContext FaceMirrorContextFor(bool saveSentCopy) =>
        new(
            Rooms:
            [
                new Room(
                    Id: "room-1",
                    Name: "Main",
                    SearchableName: "main",
                    OwnerUid: "sender",
                    MemberUids: ["sender", "receiver"],
                    MemberNicknames: new Dictionary<string, string>
                    {
                        ["sender"] = "Sender",
                        ["receiver"] = "Receiver"
                    },
                    Status: RoomStatus.Open)
            ],
            SenderUid: "sender",
            SenderNickname: "Sender",
            PartnerLabel: "Receiver",
            AllowsLocalSave: true,
            SaveSentCopy: saveSentCopy);

    private static FaceMirrorContext MultiRoomFaceMirrorContext() =>
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

    private static void AssertNoSentArchiveFiles(LocalArchive archive)
    {
        var folder = archive.FolderFor(LocalArchiveKind.Sent);
        Assert.False(Directory.Exists(folder) && Directory.EnumerateFiles(folder, "*.mp4").Any());
    }

    private sealed class FakeFaceRecorder : IFaceRecorder
    {
        public Func<MirrorState>? StateReader { get; set; }

        public MirrorState? StateAtRecordStart { get; private set; }

        public int RecordCount { get; private set; }

        public Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default)
        {
            RecordCount++;
            StateAtRecordStart = StateReader?.Invoke();
            var uniquePath = Path.Combine(
                Path.GetTempPath(),
                "PingFaceMirrorTests",
                Guid.NewGuid().ToString("N"),
                "face.mp4");
            return Task.FromResult(new FaceRecordingResult(uniquePath, duration));
        }
    }

    private sealed class FileWritingFaceRecorder : IFaceRecorder
    {
        public async Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default)
        {
            var directory = Path.Combine(
                Path.GetTempPath(),
                "PingFaceMirrorWindowClosedTests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, "face.mp4");
            await File.WriteAllBytesAsync(path, [0x00, 0x01], cancellationToken);
            return new FaceRecordingResult(path, duration);
        }
    }

    private sealed class CancelingFileWritingFaceRecorder(Action beforeReturn) : IFaceRecorder
    {
        public string? OutputPath { get; private set; }

        public async Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default)
        {
            var directory = Path.Combine(
                Path.GetTempPath(),
                "PingFaceMirrorCancelTests",
                Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            OutputPath = Path.Combine(directory, "face.mp4");
            await File.WriteAllBytesAsync(OutputPath, [0x00, 0x01], cancellationToken);
            beforeReturn();
            return new FaceRecordingResult(OutputPath, duration);
        }
    }

    private sealed class BlockingFaceRecorder : IFaceRecorder
    {
        private readonly TaskCompletionSource<FaceRecordingResult> recording = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public TaskCompletionSource RecordStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);

        public Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default)
        {
            _ = duration;
            _ = cancellationToken;
            RecordStarted.SetResult();
            return recording.Task;
        }

        public void Complete()
        {
            var uniquePath = Path.Combine(
                Path.GetTempPath(),
                "PingFaceMirrorTests",
                Guid.NewGuid().ToString("N"),
                "face.mp4");
            recording.SetResult(new FaceRecordingResult(uniquePath, TimeSpan.FromSeconds(3)));
        }
    }
}
