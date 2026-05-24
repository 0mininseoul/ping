using Ping.Windows.App.Notifications;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class IncomingMessageDedupTests
{
    [Fact]
    public async Task PollOnce_UsesPerStreamYieldedIds()
    {
        var message = Message("message-1", DateTimeOffset.UtcNow);
        var poller = new IncomingMessagePoller(_ => Task.FromResult<IReadOnlyList<VideoMessage>>([message]));
        var yieldedIds = new HashSet<string>(StringComparer.Ordinal);

        var first = await poller.PollOnceAsync(yieldedIds);
        var second = await poller.PollOnceAsync(yieldedIds);

        Assert.Single(first);
        Assert.Empty(second);
    }

    [Fact]
    public async Task PollOnce_SortsOldestFirstForStableNotificationOrder()
    {
        var older = Message("older", DateTimeOffset.UtcNow.AddSeconds(-10));
        var newer = Message("newer", DateTimeOffset.UtcNow);
        var poller = new IncomingMessagePoller(_ => Task.FromResult<IReadOnlyList<VideoMessage>>([newer, older]));

        var messages = await poller.PollOnceAsync(new HashSet<string>(StringComparer.Ordinal));

        Assert.Collection(
            messages,
            message => Assert.Equal("older", message.Id),
            message => Assert.Equal("newer", message.Id));
    }

    [Fact]
    public void NotifiedRegistry_DeduplicatesForAppSession()
    {
        var registry = new NotifiedMessageRegistry();
        var message = Message("message-1", DateTimeOffset.UtcNow);

        Assert.True(registry.TryMarkNotified(message));
        Assert.False(registry.TryMarkNotified(message));
        Assert.True(registry.Contains("message-1"));
    }

    [Fact]
    public void ActivationArguments_ParsesMessageId()
    {
        var parsed = NotificationActivationArguments.Parse("action=play&message_id=message%201");

        Assert.Equal("play", parsed.Action);
        Assert.Equal("message 1", parsed.MessageId);
    }

    private static VideoMessage Message(string id, DateTimeOffset createdAt) =>
        new()
        {
            Id = id,
            RoomId = "room-1",
            SenderUid = "sender",
            ReceiverUid = "receiver",
            SenderNickname = "Sender",
            VideoId = "video-1",
            VideoUrl = "sender/video-1.mp4",
            DurationMs = 3000,
            MirrorPosition = new MirrorPosition(0.5, 0.5),
            Status = MessageStatus.Uploaded,
            CreatedAt = createdAt,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(1),
            CaptureMode = CaptureMode.FaceOnly,
            AspectRatio = 1
        };
}
