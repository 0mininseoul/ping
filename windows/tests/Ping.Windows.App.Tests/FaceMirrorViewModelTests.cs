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

    private sealed class FakeFaceRecorder : IFaceRecorder
    {
        public Func<MirrorState>? StateReader { get; set; }

        public MirrorState? StateAtRecordStart { get; private set; }

        public Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default)
        {
            StateAtRecordStart = StateReader?.Invoke();
            return Task.FromResult(new FaceRecordingResult(Path.Combine(Path.GetTempPath(), "face.mp4"), duration));
        }
    }
}
