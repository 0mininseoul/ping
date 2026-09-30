using System.Text.Json;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class MessageRemovalPolicyTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-30T12:00:00Z");

    [Theory]
    [InlineData(299, MessageRemovalAction.Delete)]
    [InlineData(300, MessageRemovalAction.Delete)]
    [InlineData(301, MessageRemovalAction.None)]
    [InlineData(-1, MessageRemovalAction.None)]
    public void SenderWindowIncludesExactlyFiveMinutes(int seconds, MessageRemovalAction expected) =>
        Assert.Equal(expected, MessageRemovalPolicy.ForVideo("sender", "receiver", Now.AddSeconds(-seconds), "sender", Now));

    [Fact]
    public void MissingTimestampCannotGrantSenderDeletion() =>
        Assert.Equal(MessageRemovalAction.None, MessageRemovalPolicy.ForVideo("sender", "receiver", null, "sender", Now));

    [Fact]
    public void OnlyAddressedReceiverMayHideRegardlessOfAge()
    {
        Assert.Equal(MessageRemovalAction.Hide, MessageRemovalPolicy.ForVideo("sender", "receiver", Now.AddDays(-20), "receiver", Now));
        Assert.Equal(MessageRemovalAction.None, MessageRemovalPolicy.ForVideo("sender", "receiver", Now, "third-party", Now));
        Assert.Equal(MessageRemovalAction.None, MessageRemovalPolicy.ForVideo("sender", "receiver", Now, null, Now));
    }

    [Fact]
    public void ChatHasNoReceiverHidePermission()
    {
        Assert.False(MessageRemovalPolicy.CanDeleteChat("sender", Now, "receiver", Now));
        Assert.True(MessageRemovalPolicy.CanDeleteChat("sender", Now.AddMinutes(-5), "sender", Now));
        Assert.False(MessageRemovalPolicy.CanDeleteChat("sender", Now.AddMinutes(-6), "sender", Now));
    }

    [Fact]
    public void CurrentBackendAutoReplyFieldIsDecoded()
    {
        var message = JsonSerializer.Deserialize<VideoMessage>("""
            {"room_id":"room","sender_uid":"a","receiver_uid":"b","sender_nickname":"A",
             "video_id":"v","video_url":"a/v.mp4","duration_ms":3000,"mirror_position":{"x_ratio":0.5,"y_ratio":0.5},
             "status":0,"expires_at":"2026-10-30T12:00:00Z","is_auto_reply":true}
            """);
        Assert.True(message!.IsAutoReply);
    }
}
