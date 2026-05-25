using Ping.Windows.App.Notifications;
using Ping.Windows.Core.Backend;
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
        var registry = NotifiedMessageRegistry.InMemory();
        var message = Message("message-1", DateTimeOffset.UtcNow);

        Assert.True(registry.TryMarkNotified(message));
        Assert.False(registry.TryMarkNotified(message));
        Assert.True(registry.Contains("message-1"));
    }

    [Fact]
    public void NotifiedRegistry_CanForgetAfterNotificationFailure()
    {
        var registry = NotifiedMessageRegistry.InMemory();
        var message = Message("message-1", DateTimeOffset.UtcNow);

        Assert.True(registry.TryMarkNotified(message));
        registry.Forget("message-1");

        Assert.False(registry.Contains("message-1"));
        Assert.True(registry.TryMarkNotified(message));
    }

    [Fact]
    public void NotifiedRegistry_PersistsMessageIdsAcrossAppRestarts()
    {
        var path = Path.Combine(
            Path.GetTempPath(),
            "PingWindowsNotificationRegistryTests",
            Guid.NewGuid().ToString("N"),
            "NotifiedMessageIds.json");
        var message = Message("message-1", DateTimeOffset.UtcNow);

        var firstRun = new NotifiedMessageRegistry(path);
        Assert.True(firstRun.TryMarkNotified(message));

        var secondRun = new NotifiedMessageRegistry(path);

        Assert.True(secondRun.Contains("message-1"));
        Assert.False(secondRun.TryMarkNotified(message));
    }

    [Fact]
    public void NotifiedRegistry_TrimsPersistedMessageIdsToRecentWindow()
    {
        var path = Path.Combine(
            Path.GetTempPath(),
            "PingWindowsNotificationRegistryTests",
            Guid.NewGuid().ToString("N"),
            "NotifiedMessageIds.json");
        var registry = new NotifiedMessageRegistry(path);

        for (var index = 0; index < 305; index++)
        {
            Assert.True(registry.TryMarkNotified(Message($"message-{index}", DateTimeOffset.UtcNow)));
        }

        var reloaded = new NotifiedMessageRegistry(path);

        Assert.False(reloaded.Contains("message-0"));
        Assert.True(reloaded.Contains("message-304"));
    }

    [Fact]
    public void NotificationController_DeduplicatesShownMessagesInPortableTests()
    {
        using var controller = new NotificationController(
            (_, _) => Task.CompletedTask,
            registry: NotifiedMessageRegistry.InMemory());
        var message = Message("message-1", DateTimeOffset.UtcNow);

        Assert.True(controller.TryShowIncoming(message));
        Assert.False(controller.TryShowIncoming(message));
    }

    [Fact]
    public async Task IncomingChatPoller_NotifiesLatestUnreadChatPerRoom()
    {
        var rpc = new RecordingChatRpcClient();
        var chatService = new ChatMessageService(rpc);
        var roomService = new RoomService(rpc);
        var poller = new IncomingChatPoller(chatService, roomService, () => "receiver");
        var yieldedIds = new HashSet<string>(StringComparer.Ordinal);

        var first = await poller.PollOnceAsync(yieldedIds);
        var second = await poller.PollOnceAsync(yieldedIds);

        var notification = Assert.Single(first);
        Assert.Equal("chat-new", notification.Message.Id);
        Assert.Equal("Main", notification.RoomName);
        Assert.Equal(2, notification.UnreadCount);
        Assert.Empty(second);
    }

    [Fact]
    public void NotificationController_DeduplicatesShownChatsInPortableTests()
    {
        using var controller = new NotificationController(
            (_, _) => Task.CompletedTask,
            chatRegistry: NotifiedChatRegistry.InMemory());
        var notification = new IncomingChatNotification(Chat("chat-1", "room-1", "sender", "hello", DateTimeOffset.UtcNow), "Main", 1);

        Assert.True(controller.TryShowIncomingChat(notification));
        Assert.False(controller.TryShowIncomingChat(notification));
    }

    [Fact]
    public void NotifiedChatRegistry_PersistsChatIdsAcrossAppRestarts()
    {
        var path = Path.Combine(
            Path.GetTempPath(),
            "PingWindowsNotificationRegistryTests",
            Guid.NewGuid().ToString("N"),
            "NotifiedChatIds.json");
        var chat = Chat("chat-1", "room-1", "sender", "hello", DateTimeOffset.UtcNow);

        var firstRun = new NotifiedChatRegistry(path);
        Assert.True(firstRun.TryMarkNotified(chat));

        var secondRun = new NotifiedChatRegistry(path);

        Assert.True(secondRun.Contains("chat-1"));
        Assert.False(secondRun.TryMarkNotified(chat));
    }

    [Fact]
    public void NotifiedChatRegistry_TrimsPersistedChatIdsToRecentWindow()
    {
        var path = Path.Combine(
            Path.GetTempPath(),
            "PingWindowsNotificationRegistryTests",
            Guid.NewGuid().ToString("N"),
            "NotifiedChatIds.json");
        var registry = new NotifiedChatRegistry(path);

        for (var index = 0; index < 505; index++)
        {
            Assert.True(registry.TryMarkNotified(Chat($"chat-{index}", "room-1", "sender", "hello", DateTimeOffset.UtcNow)));
        }

        var reloaded = new NotifiedChatRegistry(path);

        Assert.False(reloaded.Contains("chat-0"));
        Assert.True(reloaded.Contains("chat-504"));
    }

    [Fact]
    public void ActivationArguments_ParsesMessageId()
    {
        var parsed = NotificationActivationArguments.Parse("action=play&message_id=message%201");

        Assert.Equal("play", parsed.Action);
        Assert.Equal("message 1", parsed.MessageId);
        Assert.True(parsed.HasValues);
    }

    [Fact]
    public void ActivationArguments_ParsesChatTarget()
    {
        var parsed = NotificationActivationArguments.Parse("action=chat&chat_id=chat%201&room_id=room%201");

        Assert.Equal("chat", parsed.Action);
        Assert.Equal("chat 1", parsed.ChatId);
        Assert.Equal("room 1", parsed.RoomId);
        Assert.True(parsed.HasValues);
    }

    [Fact]
    public void ActivationArguments_IgnoresDuplicateKeysWithoutThrowing()
    {
        var parsed = NotificationActivationArguments.Parse("action=play&message_id=message-1&message_id=message-2");

        Assert.Equal("play", parsed.Action);
        Assert.Equal("message-1", parsed.MessageId);
        Assert.True(parsed.HasValues);
    }

    [Fact]
    public void ActivationArguments_ReadsWindowsAppSdkDictionary()
    {
        var parsed = NotificationActivationArguments.From(new Dictionary<string, string>
        {
            ["action"] = "play",
            ["message_id"] = "message-1"
        });

        Assert.Equal("play", parsed.Action);
        Assert.Equal("message-1", parsed.MessageId);
        Assert.True(parsed.HasValues);
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

    private static ChatMessage Chat(string id, string roomId, string senderUid, string body, DateTimeOffset createdAt) =>
        new()
        {
            Id = id,
            RoomId = roomId,
            SenderUid = senderUid,
            SenderNickname = senderUid,
            Body = body,
            CreatedAt = createdAt
        };

    private sealed class RecordingChatRpcClient : ISupabaseRpcClient
    {
        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            object result = function switch
            {
                "ping_unread_chat_counts" => new[]
                {
                    new UnreadChatCount("room-1", 2)
                },
                "ping_my_rooms" => new[]
                {
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
                },
                "ping_room_chat_messages" => new[]
                {
                    Chat("own-new", "room-1", "receiver", "mine", DateTimeOffset.UtcNow.AddSeconds(2)),
                    Chat("chat-new", "room-1", "sender", "new", DateTimeOffset.UtcNow.AddSeconds(1)),
                    Chat("chat-old", "room-1", "sender", "old", DateTimeOffset.UtcNow)
                },
                _ => Array.Empty<object>()
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }

        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }
    }
}
