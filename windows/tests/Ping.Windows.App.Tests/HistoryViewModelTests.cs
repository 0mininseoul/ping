using System.Text.Json;
using Ping.Windows.App.History;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class HistoryViewModelTests
{
    private static readonly DateTimeOffset BaseTime = new(2026, 1, 1, 10, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task LoadAsync_SelectsPreferredRoomAndMarksItRead()
    {
        var rpc = new RecordingHistoryRpcClient();
        var viewModel = ViewModel(rpc);

        await viewModel.LoadAsync("room-2");

        Assert.Equal("room-2", viewModel.SelectedRoom?.Id);
        Assert.Equal("Project", viewModel.SelectedRoomName);
        Assert.Collection(
            viewModel.Videos,
            video =>
            {
                Assert.Equal("video-message-2", video.Message.Id);
                Assert.Collection(video.Reactions, reaction => Assert.Equal("👍", reaction.Emoji));
            });
        Assert.Collection(
            viewModel.Chats,
            chat =>
            {
                Assert.Equal("chat-2", chat.Message.Id);
                Assert.Equal("Sender: Screen + face video", chat.ReplyPreview);
                Assert.Collection(chat.Reactions, reaction => Assert.Equal("❤️", reaction.Emoji));
            });
        Assert.Collection(
            viewModel.Timeline,
            row => Assert.Equal("video-message-2", row.Video?.Message.Id),
            row => Assert.Equal("chat-2", row.Chat?.Message.Id));
        Assert.Equal(["room-2"], rpc.MarkedReadRoomIds);
        Assert.Contains("1 videos, 1 chats, 2 reactions.", viewModel.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public async Task SelectRoomAsync_LoadsRoomsWhenNeeded()
    {
        var rpc = new RecordingHistoryRpcClient();
        var viewModel = ViewModel(rpc);

        await viewModel.SelectRoomAsync("room-1");

        Assert.Equal("room-1", viewModel.SelectedRoom?.Id);
        Assert.Equal("Main", viewModel.SelectedRoomName);
        Assert.Equal(["room-1"], rpc.MarkedReadRoomIds);
    }

    [Fact]
    public void ChatHistoryItem_TracksImagePathInPortableTests()
    {
        var localPath = Path.Combine(Path.GetTempPath(), "Ping", "history-test.png");
        var item = new ChatHistoryItem(
            new ChatMessage
            {
                Id = "chat-image",
                RoomId = "room-1",
                SenderUid = "sender",
                SenderNickname = "Sender",
                Body = "image",
                MediaPath = "sender/chat-images/chat-image.png",
                MediaMimeType = "image/png",
                MediaFileName = "photo.png",
                CreatedAt = DateTimeOffset.UtcNow
            },
            ["👍"],
            []);

        Assert.True(item.AttachmentVisibility);
        Assert.False(item.ImageVisibility);

        item.SetImagePath(localPath);

        Assert.True(item.ImageVisibility);
        Assert.Equal(new Uri(Path.GetFullPath(localPath)), item.ImageSource);
        Assert.Equal("photo.png", item.AttachmentStatus);
    }

    [Fact]
    public async Task SendChatAsync_PreservesReplyTargetUntilSendSucceeds()
    {
        var rpc = new RecordingHistoryRpcClient();
        var viewModel = ViewModel(rpc);
        await viewModel.LoadAsync("room-2");

        viewModel.BeginReplyToChat(viewModel.Chats.Single());
        Assert.Equal("Sender: chat chat-2", viewModel.ReplyPreviewText);

        await viewModel.SendChatAsync("reply body");

        Assert.Null(viewModel.ReplyTarget);
        var sent = Assert.Single(rpc.SentChatBodies);
        var json = JsonSerializer.SerializeToElement(sent, JsonOptions.Supabase);
        Assert.Equal("room-2", json.GetProperty("room_uuid").GetString());
        Assert.Equal("reply body", json.GetProperty("body_text").GetString());
        Assert.Equal("chat-2", json.GetProperty("reply_chat_uuid").GetString());
    }

    [Fact]
    public async Task DeleteChatAsync_OnlyDeletesOwnRows()
    {
        var rpc = new RecordingHistoryRpcClient();
        var viewModel = ViewModel(rpc);
        await viewModel.LoadAsync("room-1");

        await viewModel.DeleteChatAsync(viewModel.Chats.Single());

        Assert.Equal(["chat-1"], rpc.DeletedChatIds);
        Assert.Empty(viewModel.Chats);
        Assert.Collection(viewModel.Timeline, row => Assert.Equal("video-message-1", row.Video?.Message.Id));
    }

    [Fact]
    public async Task DeleteVideoAsync_HidesReceivedRowsForCurrentUser()
    {
        var rpc = new RecordingHistoryRpcClient();
        var viewModel = ViewModel(rpc);
        await viewModel.LoadAsync("room-2");

        await viewModel.DeleteVideoAsync(viewModel.Videos.Single());

        Assert.Equal(["video-message-2"], rpc.HiddenVideoIds);
        Assert.Empty(viewModel.Videos);
        Assert.Collection(viewModel.Timeline, row => Assert.Equal("chat-2", row.Chat?.Message.Id));
    }

    [Fact]
    public async Task HistoryAutoRefreshCoordinator_DoesNotOverlapRefreshes()
    {
        var calls = 0;
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var coordinator = new HistoryAutoRefreshCoordinator(
            TimeSpan.FromSeconds(1),
            async _ =>
            {
                Interlocked.Increment(ref calls);
                entered.TrySetResult();
                await release.Task;
            });

        var first = coordinator.RefreshOnceAsync();
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await coordinator.RefreshOnceAsync().WaitAsync(TimeSpan.FromSeconds(1));

        Assert.Equal(1, Volatile.Read(ref calls));

        release.SetResult();
        await first.WaitAsync(TimeSpan.FromSeconds(1));
        await coordinator.RefreshOnceAsync().WaitAsync(TimeSpan.FromSeconds(1));

        Assert.Equal(2, Volatile.Read(ref calls));
    }

    [Fact]
    public async Task HistoryAutoRefreshCoordinator_StartIsIdempotentAndStopCancelsDelay()
    {
        var refreshCalls = 0;
        var delayCalls = 0;
        var delayEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var coordinator = new HistoryAutoRefreshCoordinator(
            TimeSpan.FromSeconds(5),
            _ =>
            {
                Interlocked.Increment(ref refreshCalls);
                return Task.CompletedTask;
            },
            async (_, token) =>
            {
                Interlocked.Increment(ref delayCalls);
                delayEntered.TrySetResult();
                await Task.Delay(Timeout.InfiniteTimeSpan, token);
            });

        coordinator.Start();
        coordinator.Start();
        await delayEntered.Task.WaitAsync(TimeSpan.FromSeconds(1));

        Assert.True(coordinator.IsRunning);
        Assert.Equal(1, Volatile.Read(ref delayCalls));

        await coordinator.StopAsync().WaitAsync(TimeSpan.FromSeconds(1));

        Assert.False(coordinator.IsRunning);
        Assert.Equal(0, Volatile.Read(ref refreshCalls));
    }

    private static HistoryViewModel ViewModel(RecordingHistoryRpcClient rpc) =>
        new(
            new RoomService(rpc),
            new MessageService(rpc, new ThrowingStorageService()),
            new ChatMessageService(rpc),
            new ReactionService(rpc),
            new StorageService(new SupabaseClient()),
            () => "receiver");

    private static VideoMessage VideoMessage(string id, string roomId, DateTimeOffset createdAt) =>
        new()
        {
            Id = id,
            RoomId = roomId,
            SenderUid = "sender",
            ReceiverUid = "receiver",
            SenderNickname = "Sender",
            VideoId = $"{id}-asset",
            VideoUrl = $"sender/{id}.mp4",
            DurationMs = 3000,
            MirrorPosition = new MirrorPosition(0.5, 0.5),
            Status = MessageStatus.Uploaded,
            CreatedAt = createdAt,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(1),
            CaptureMode = CaptureMode.ScreenFace,
            AspectRatio = 1.6
        };

    private static ChatMessage ChatMessage(
        string id,
        string roomId,
        string senderUid = "sender",
        string? replyToVideoId = null,
        DateTimeOffset? createdAt = null) =>
        new()
        {
            Id = id,
            RoomId = roomId,
            SenderUid = senderUid,
            SenderNickname = senderUid == "receiver" ? "Receiver" : "Sender",
            Body = $"chat {id}",
            ReplyToVideoId = replyToVideoId,
            CreatedAt = createdAt ?? BaseTime
        };

    private sealed class RecordingHistoryRpcClient : ISupabaseRpcClient
    {
        public List<string> MarkedReadRoomIds { get; } = [];

        public List<object> SentChatBodies { get; } = [];

        public List<string> DeletedChatIds { get; } = [];

        public List<string> DeletedVideoIds { get; } = [];

        public List<string> HiddenVideoIds { get; } = [];

        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(
            string function,
            object? body = null,
            CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            object result = function switch
            {
                "ping_my_rooms" => new[]
                {
                    Room("room-1", "Main"),
                    Room("room-2", "Project")
                },
                "ping_room_messages" => RoomId(body) switch
                {
                    "room-1" => new[] { VideoMessage("video-message-1", "room-1", BaseTime.AddMinutes(1)) },
                    "room-2" => new[] { VideoMessage("video-message-2", "room-2", BaseTime.AddMinutes(1)) },
                    _ => []
                },
                "ping_room_chat_messages" => RoomId(body) switch
                {
                    "room-1" => new[] { ChatMessage("chat-1", "room-1", senderUid: "receiver", createdAt: BaseTime.AddMinutes(2)) },
                    "room-2" => new[] { ChatMessage("chat-2", "room-2", replyToVideoId: "video-message-2", createdAt: BaseTime.AddMinutes(2)) },
                    _ => []
                },
                "ping_message_reactions" => ReactionsFor(body),
                _ => Array.Empty<object>()
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }

        public Task<T> RpcValueAsync<T>(
            string function,
            object? body = null,
            CancellationToken cancellationToken = default)
        {
            _ = function;
            _ = cancellationToken;
            if (function == "ping_send_chat")
            {
                SentChatBodies.Add(body ?? new { });
                return Task.FromResult((T)(object)"new-chat-id");
            }

            throw new NotSupportedException();
        }

        public Task RpcVoidAsync(
            string function,
            object? body = null,
            CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            if (function == "ping_mark_room_read")
            {
                MarkedReadRoomIds.Add(RoomId(body));
            }
            else if (function == "ping_delete_chat")
            {
                DeletedChatIds.Add(ChatId(body));
            }
            else if (function == "ping_delete_message")
            {
                DeletedVideoIds.Add(MessageId(body));
            }
            else if (function == "ping_hide_message_for_receiver")
            {
                HiddenVideoIds.Add(MessageId(body));
            }

            return Task.CompletedTask;
        }

        private static Room Room(string id, string name) =>
            new(
                Id: id,
                Name: name,
                SearchableName: name.ToLowerInvariant(),
                OwnerUid: "sender",
                MemberUids: ["sender", "receiver"],
                MemberNicknames: new Dictionary<string, string>
                {
                    ["sender"] = "Sender",
                    ["receiver"] = "Receiver"
                },
                Status: RoomStatus.Open);

        private static IReadOnlyList<MessageReaction> ReactionsFor(object? body)
        {
            var json = JsonSerializer.SerializeToElement(body, JsonOptions.Supabase);
            var chatIds = json.GetProperty("chat_ids").EnumerateArray().Select(item => item.GetString()).ToHashSet(StringComparer.Ordinal);
            var videoIds = json.GetProperty("video_ids").EnumerateArray().Select(item => item.GetString()).ToHashSet(StringComparer.Ordinal);
            var reactions = new List<MessageReaction>();
            if (chatIds.Contains("chat-2"))
            {
                reactions.Add(new MessageReaction(ReactionTargetKind.Chat, "chat-2", "❤️", 2, true));
            }

            if (videoIds.Contains("video-message-2"))
            {
                reactions.Add(new MessageReaction(ReactionTargetKind.Video, "video-message-2", "👍", 1, false));
            }

            return reactions;
        }

        private static string RoomId(object? body)
        {
            var json = JsonSerializer.SerializeToElement(body, JsonOptions.Supabase);
            return json.GetProperty("room_uuid").GetString()
                ?? throw new InvalidOperationException("RPC body did not include room_uuid.");
        }

        private static string ChatId(object? body)
        {
            var json = JsonSerializer.SerializeToElement(body, JsonOptions.Supabase);
            return json.GetProperty("chat_uuid").GetString()
                ?? throw new InvalidOperationException("RPC body did not include chat_uuid.");
        }

        private static string MessageId(object? body)
        {
            var json = JsonSerializer.SerializeToElement(body, JsonOptions.Supabase);
            return json.GetProperty("message_uuid").GetString()
                ?? throw new InvalidOperationException("RPC body did not include message_uuid.");
        }
    }

    private sealed class ThrowingStorageService : IStorageService
    {
        public Task<string> UploadVideoAsync(
            string localVideoPath,
            string senderUid,
            string videoId,
            IReadOnlyCollection<string> authorizedReceiverUids,
            DateTimeOffset expiresAt,
            CancellationToken cancellationToken = default)
        {
            _ = localVideoPath;
            _ = senderUid;
            _ = videoId;
            _ = authorizedReceiverUids;
            _ = expiresAt;
            _ = cancellationToken;
            throw new NotSupportedException();
        }
    }
}
