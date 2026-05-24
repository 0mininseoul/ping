using Ping.Windows.App.Playback;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class PlaybackViewModelTests
{
    [Fact]
    public async Task PlaybackEnded_MarksSeenOnceAndRequestsClose()
    {
        var markSeenCount = 0;
        var viewModel = new PlaybackViewModel(
            Message(CaptureMode.FaceOnly, aspectRatio: 1),
            "clip.mp4",
            _ =>
            {
                markSeenCount++;
                return Task.CompletedTask;
            });
        var didClose = false;
        viewModel.CloseRequested += (_, _) => didClose = true;

        await viewModel.HandlePlaybackEndedAsync();
        await viewModel.HandlePlaybackEndedAsync();

        Assert.Equal(1, markSeenCount);
        Assert.True(didClose);
    }

    [Fact]
    public void ScreenFace_UsesStoredAspectRatio()
    {
        var viewModel = new PlaybackViewModel(
            Message(CaptureMode.ScreenFace, aspectRatio: 16.0 / 9.0),
            "clip.mp4",
            _ => Task.CompletedTask);

        Assert.True(viewModel.IsScreenFace);
        Assert.Equal(16.0 / 9.0, viewModel.AspectRatio);
    }

    private static VideoMessage Message(CaptureMode captureMode, double? aspectRatio) =>
        new()
        {
            Id = "message-1",
            RoomId = "room-1",
            SenderUid = "sender",
            ReceiverUid = "receiver",
            SenderNickname = "Sender",
            VideoId = "video-1",
            VideoUrl = "sender/video-1.mp4",
            DurationMs = 3000,
            MirrorPosition = new MirrorPosition(0.5, 0.5),
            Status = MessageStatus.Uploaded,
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(1),
            CaptureMode = captureMode,
            AspectRatio = aspectRatio
        };
}
