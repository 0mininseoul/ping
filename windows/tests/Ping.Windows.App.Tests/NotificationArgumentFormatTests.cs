using Ping.Windows.App.Notifications;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class NotificationArgumentFormatTests
{
    [Theory]
    [InlineData("action=chat&chat_id=native-chat&room_id=native-room", "chat&chat_id=native-chat&room_id=native-room", "chat", null, "native-chat", "native-room")]
    [InlineData("action=play&message_id=native-video", "play&message_id=native-video", "play", "native-video", null, null)]
    public void PingQueryPayloadUsesRawArgumentsWhenSdkMapTreatsAmpersandsAsPartOfAction(
        string argument, string sdkAction, string action, string? messageId, string? chatId, string? roomId)
    {
        var result = NotificationActivationArguments.From(argument, new Dictionary<string, string> { ["action"] = sdkAction });
        Assert.Equal(new NotificationActivationArguments(action, messageId, chatId, roomId), result);
    }

    [Fact]
    public void SdkBuilderDictionaryRemainsUsableWithSemicolonArguments()
    {
        var result = NotificationActivationArguments.From("action=chat;chat_id=native-chat;room_id=native-room",
            new Dictionary<string, string> { ["action"] = "chat", ["chat_id"] = "native-chat", ["room_id"] = "native-room" });
        Assert.Equal(new NotificationActivationArguments("chat", null, "native-chat", "native-room"), result);
    }

    [Fact]
    public void CompleteSdkTargetIsPreservedWhenRawArgumentsOnlyContainTheAction()
    {
        var result = NotificationActivationArguments.From("action=chat",
            new Dictionary<string, string> { ["action"] = "chat", ["chat_id"] = "native-chat", ["room_id"] = "native-room" });
        Assert.Equal(new NotificationActivationArguments("chat", null, "native-chat", "native-room"), result);
    }
}
