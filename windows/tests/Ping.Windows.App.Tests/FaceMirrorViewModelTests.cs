using Ping.Windows.App.Capture;
using Ping.Windows.Core.Backend;
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
    public async Task Enter_WhenSendFails_KeepsFailedStateWithRetryMessage()
    {
        var model = new FaceMirrorViewModel(
            FaceMirrorContextFor(saveSentCopy: false),
            new FakeFaceRecorder(),
            (_, _) => throw new InvalidOperationException("Upload failed."));

        await model.HandleEnterAsync();

        Assert.Equal(MirrorState.Failed, model.State);
        Assert.Contains("Upload failed", model.StatusMessage, StringComparison.OrdinalIgnoreCase);
        Assert.False(model.IsCloseRequested);
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
        Assert.True(model.SelectNextTarget());
        Assert.Equal("Main", model.PartnerLabel);
        Assert.True(model.SelectNextTarget());
        Assert.Equal("Design", model.PartnerLabel);
        Assert.True(model.SelectNextTarget());
        Assert.Equal("All rooms", model.PartnerLabel);
        Assert.True(model.SelectTargetAtIndex(0));
        Assert.True(model.SelectAllTargets());
        Assert.Equal("All rooms", model.PartnerLabel);
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

    private sealed class FakeFaceRecorder : IFaceRecorder
    {
        public Func<MirrorState>? StateReader { get; set; }

        public MirrorState? StateAtRecordStart { get; private set; }

        public Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default)
        {
            StateAtRecordStart = StateReader?.Invoke();
            var uniquePath = Path.Combine(
                Path.GetTempPath(),
                "PingFaceMirrorTests",
                Guid.NewGuid().ToString("N"),
                "face.mp4");
            return Task.FromResult(new FaceRecordingResult(uniquePath, duration));
        }
    }
}
