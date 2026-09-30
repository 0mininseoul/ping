using System.Text.Json;
using Ping.Windows.App.History;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class HistorySnapshotTests
{
    [Fact]
    public async Task FailedRefreshKeepsTimelineSelectionAndReply()
    {
        var rpc = new SnapshotRpc();
        var viewModel = Create(rpc);
        await viewModel.LoadAsync("a");
        var row = Assert.Single(viewModel.Timeline);
        viewModel.SelectedTimelineItem = row;
        viewModel.BeginReplyToChat(row.Chat!);
        var reply = viewModel.ReplyTarget;
        rpc.Fail = true;

        await Assert.ThrowsAsync<HttpRequestException>(() => viewModel.LoadSelectedRoomAsync());

        Assert.Same(row, Assert.Single(viewModel.Timeline));
        Assert.Same(row, viewModel.SelectedTimelineItem);
        Assert.Same(reply, viewModel.ReplyTarget);
    }

    [Fact]
    public async Task LateRoomResponseCannotOverwriteNewSelectionOrMarkOldRoomRead()
    {
        var rpc = new SnapshotRpc();
        var viewModel = Create(rpc);
        await viewModel.LoadAsync("a");
        rpc.ReadRooms.Clear();
        rpc.PauseA = true;
        var oldLoad = viewModel.LoadSelectedRoomAsync();
        await rpc.AEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));

        await viewModel.SelectRoomAsync("b");
        rpc.AReleased.SetResult();
        await oldLoad;

        Assert.Equal("b", viewModel.SelectedRoom!.Id);
        Assert.Equal("chat-b", Assert.Single(viewModel.Timeline).Chat!.Message.Id);
        Assert.DoesNotContain("a", rpc.ReadRooms);
    }

    [Fact]
    public async Task FailedRoomListRefreshKeepsExistingConversations()
    {
        var rpc = new SnapshotRpc();
        var viewModel = Create(rpc);
        await viewModel.LoadAsync("b");
        rpc.Fail = true;

        await Assert.ThrowsAsync<HttpRequestException>(() => viewModel.LoadAsync("b"));

        Assert.Equal(2, viewModel.Rooms.Count);
        Assert.Equal("b", viewModel.SelectedRoom!.Id);
        Assert.Equal("chat-b", Assert.Single(viewModel.Timeline).Chat!.Message.Id);
    }

    [Fact]
    public async Task ForegroundReadPolicyTracksActivationWithoutReloadingConversation()
    {
        var rpc = new SnapshotRpc();
        var foreground = false;
        var viewModel = Create(rpc, _ => foreground);
        await viewModel.LoadAsync("a");
        Assert.Empty(rpc.ReadRooms);

        foreground = true;
        await viewModel.MarkVisibleRoomReadAsync();

        Assert.Equal(["a"], rpc.ReadRooms);
        Assert.Equal(0, viewModel.SelectedRoom!.UnreadCount);
        foreground = false;
        await viewModel.LoadSelectedRoomAsync();
        Assert.Equal(["a"], rpc.ReadRooms);
    }

    [Fact]
    public async Task FailedDifferentRoomLoadDoesNotExposeOldMessagesUnderNewRoom()
    {
        var rpc = new SnapshotRpc();
        var viewModel = Create(rpc);
        await viewModel.LoadAsync("a");
        rpc.Fail = true;

        await Assert.ThrowsAsync<HttpRequestException>(() => viewModel.SelectRoomAsync("b"));

        Assert.Equal("b", viewModel.SelectedRoom!.Id);
        Assert.False(viewModel.TimelineVisibility);
        Assert.Equal("chat-a", Assert.Single(viewModel.Timeline).Chat!.Message.Id);
    }

    [Fact]
    public async Task MissingVisibilityProviderDoesNotMarkRoomRead()
    {
        var rpc = new SnapshotRpc();
        var viewModel = Create(rpc);

        await viewModel.LoadAsync("a");

        Assert.Empty(rpc.ReadRooms);
        Assert.Equal(2, viewModel.SelectedRoom!.UnreadCount);
    }

    private static HistoryViewModel Create(SnapshotRpc rpc, Func<string, bool>? canMarkRoomRead = null)
    {
        var storage = new StorageStub();
        return new HistoryViewModel(new RoomService(rpc), new MessageService(rpc, storage),
            new ChatMessageService(rpc), new ReactionService(rpc), storage, () => "me", canMarkRoomRead: canMarkRoomRead);
    }

    private sealed class SnapshotRpc : ISupabaseRpcClient
    {
        public bool Fail { get; set; }
        public bool PauseA { get; set; }
        public TaskCompletionSource AEntered { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource AReleased { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public List<string> ReadRooms { get; } = [];

        public async Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (Fail) throw new HttpRequestException("offline");
            var roomId = body is null ? null : JsonSerializer.SerializeToElement(body, JsonOptions.Supabase)
                .TryGetProperty("room_uuid", out var id) ? id.GetString() : null;
            if (PauseA && roomId == "a" && function == "ping_room_messages")
            {
                AEntered.TrySetResult();
                await AReleased.Task.WaitAsync(cancellationToken);
            }
            object result = function switch
            {
                "ping_my_rooms" => new[] { Room("a"), Room("b") },
                "ping_room_messages" => Array.Empty<VideoMessage>(),
                "ping_room_chat_messages" => new[]
                {
                    new ChatMessage { Id = "chat-" + roomId, RoomId = roomId!, SenderUid = "peer", SenderNickname = "Peer",
                        Body = "hello", CreatedAt = DateTimeOffset.UtcNow }
                },
                "ping_message_reactions" => Array.Empty<MessageReaction>(),
                _ => throw new NotSupportedException(function)
            };
            return (IReadOnlyList<T>)result;
        }

        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function == "ping_mark_room_read")
                ReadRooms.Add(JsonSerializer.SerializeToElement(body, JsonOptions.Supabase).GetProperty("room_uuid").GetString()!);
            return Task.CompletedTask;
        }
        private static Room Room(string id) => new(id, id, id, "me", ["me", "peer"],
            new Dictionary<string, string> { ["me"] = "Me", ["peer"] = "Peer" }, RoomStatus.Open, UnreadCount: 2);
    }

    private sealed class StorageStub : IStorageService, IChatMediaStorageService
    {
        public Task<string> UploadVideoAsync(string localVideoPath, string senderUid, string videoId,
            IReadOnlyCollection<string> authorizedReceiverUids, DateTimeOffset expiresAt, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task DeleteVideoAsync(string remotePath, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<ChatImageUpload> UploadChatImageAsync(string localImagePath, string senderUid, string messageId, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<string> DownloadChatMediaAsync(string remotePath, string fileExtension, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task DeleteChatMediaAsync(string remotePath, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
