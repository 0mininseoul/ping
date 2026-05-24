using System.Text.Json;
using Ping.Windows.App.History;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class HistoryViewModelTests
{
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
                Assert.Collection(chat.Reactions, reaction => Assert.Equal("❤️", reaction.Emoji));
            });
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

    private static HistoryViewModel ViewModel(RecordingHistoryRpcClient rpc) =>
        new(
            new RoomService(rpc),
            new MessageService(rpc, new ThrowingStorageService()),
            new ChatMessageService(rpc),
            new ReactionService(rpc),
            new StorageService(new SupabaseClient()),
            () => "receiver");

    private static VideoMessage VideoMessage(string id, string roomId) =>
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
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = DateTimeOffset.UtcNow.AddDays(1),
            CaptureMode = CaptureMode.ScreenFace,
            AspectRatio = 1.6
        };

    private static ChatMessage ChatMessage(string id, string roomId) =>
        new()
        {
            Id = id,
            RoomId = roomId,
            SenderUid = "sender",
            SenderNickname = "Sender",
            Body = $"chat {id}",
            CreatedAt = DateTimeOffset.UtcNow
        };

    private sealed class RecordingHistoryRpcClient : ISupabaseRpcClient
    {
        public List<string> MarkedReadRoomIds { get; } = [];

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
                    "room-1" => new[] { VideoMessage("video-message-1", "room-1") },
                    "room-2" => new[] { VideoMessage("video-message-2", "room-2") },
                    _ => []
                },
                "ping_room_chat_messages" => RoomId(body) switch
                {
                    "room-1" => new[] { ChatMessage("chat-1", "room-1") },
                    "room-2" => new[] { ChatMessage("chat-2", "room-2") },
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
            _ = body;
            _ = cancellationToken;
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
