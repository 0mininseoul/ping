using System.Text.Json;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class RoomContractTests
{
    [Fact]
    public async Task RoomService_UsesMacOSRoomRpcBodies()
    {
        var rpc = new RecordingSocialRpcClient();
        var service = new RoomService(rpc);

        await service.CreateRoomAsync(" Main Room ", "Youngmin");
        await service.MyRoomsAsync();
        await service.SearchOpenRoomsAsync("Main");
        await service.JoinRoomAsync("room-id", "Youngmin");
        await service.LeaveRoomAsync("room-id");
        await service.RenameRoomAsync("room-id", "Renamed Room");

        Assert.Equal(
            [
                "ping_create_room",
                "ping_my_rooms",
                "ping_search_open_rooms",
                "ping_join_room",
                "ping_leave_room",
                "ping_rename_room"
            ],
            rpc.Calls.Select(call => call.Function));
        Assert.Equal(
            """{"room_name":"Main Room","searchable_room_name":"main room","owner_nickname":"Youngmin"}""",
            JsonSerializer.Serialize(rpc.Calls[0].Body, JsonOptions.Supabase));
        Assert.Equal(
            """{"room_uuid":"room-id","new_name":"Renamed Room","new_searchable_name":"renamed room"}""",
            JsonSerializer.Serialize(rpc.Calls[5].Body, JsonOptions.Supabase));
    }

    [Fact]
    public async Task InvitationService_UsesMacOSInvitationRpcBodies()
    {
        var rpc = new RecordingSocialRpcClient();
        var service = new InvitationService(rpc);

        await service.SendAsync("receiver", "room-id", "Youngmin", "Main");
        await service.InviteUserAsync("receiver", "Youngmin", "Main");
        await service.IncomingAsync();
        await service.AcceptAsync("invite-id", "Receiver");
        await service.RejectAsync("invite-id");
        await service.CreateInviteLinkAsync("room-id");
        await service.AcceptInviteLinkAsync("token", "Receiver");

        Assert.Equal(
            [
                "ping_send_invitation",
                "ping_invite_user",
                "ping_incoming_invitations",
                "ping_accept_invitation",
                "ping_reject_invitation",
                "ping_create_invite_link",
                "ping_accept_invite_link"
            ],
            rpc.Calls.Select(call => call.Function));
        Assert.Equal(
            """{"target_uid":"receiver","inviter_nickname_text":"Youngmin","room_name_text":"Main","searchable_room_name":"main"}""",
            JsonSerializer.Serialize(rpc.Calls[1].Body, JsonOptions.Supabase));
        Assert.Equal(
            """{"invite_token":"token","nickname_text":"Receiver"}""",
            JsonSerializer.Serialize(rpc.Calls[6].Body, JsonOptions.Supabase));
    }

    [Fact]
    public async Task ChatAndReactionServices_UseMacOSRpcBodies()
    {
        var rpc = new RecordingSocialRpcClient();
        var chat = new ChatMessageService(rpc);
        var reactions = new ReactionService(rpc);

        await chat.SendChatAsync(
            "room-id",
            "hello",
            replyToChatId: "chat-reply",
            media: new ChatMediaPayload(
                "sender/chat-images/message.png",
                "image/png",
                Width: 640,
                Height: 480,
                FileName: "message.png"));
        await chat.RoomChatMessagesAsync("room-id", limit: 25);
        await chat.DeleteChatAsync("chat-id");
        await chat.MarkRoomReadAsync("room-id");
        await chat.UnreadChatCountsAsync();
        await reactions.ToggleAsync(ReactionTargetKind.Video, "video-id", "+1");
        await reactions.ReactionsAsync(["chat-id"], ["video-id"]);

        Assert.Equal(
            [
                "ping_send_chat",
                "ping_room_chat_messages",
                "ping_delete_chat",
                "ping_mark_room_read",
                "ping_unread_chat_counts",
                "ping_react",
                "ping_message_reactions"
            ],
            rpc.Calls.Select(call => call.Function));
        var chatBody = JsonSerializer.Serialize(rpc.Calls[0].Body, JsonOptions.Supabase);
        Assert.Contains("\"room_uuid\":\"room-id\"", chatBody, StringComparison.Ordinal);
        Assert.Contains("\"reply_chat_uuid\":\"chat-reply\"", chatBody, StringComparison.Ordinal);
        Assert.Contains("\"media_path_text\":\"sender/chat-images/message.png\"", chatBody, StringComparison.Ordinal);
        using var reactionBody = JsonDocument.Parse(JsonSerializer.Serialize(rpc.Calls[5].Body, JsonOptions.Supabase));
        Assert.Equal("video", reactionBody.RootElement.GetProperty("target_kind").GetString());
        Assert.Equal("video-id", reactionBody.RootElement.GetProperty("target_uuid").GetString());
        Assert.Equal("+1", reactionBody.RootElement.GetProperty("emoji_text").GetString());
    }

    [Fact]
    public void MessageReaction_DecodesCurrentSqlReturnShape()
    {
        const string payload = """
        [{"target_kind":"video","target_id":"00000000-0000-0000-0000-000000000001","emoji":"+1","total_count":2,"my_reacted":true}]
        """;

        var reactions = JsonSerializer.Deserialize<IReadOnlyList<MessageReaction>>(payload, JsonOptions.Supabase);

        Assert.NotNull(reactions);
        var reaction = Assert.Single(reactions);
        Assert.Equal(ReactionTargetKind.Video, reaction.TargetKind);
        Assert.Equal("00000000-0000-0000-0000-000000000001", reaction.TargetId);
        Assert.Equal("+1", reaction.Emoji);
        Assert.Equal(2, reaction.TotalCount);
        Assert.True(reaction.MyReacted);
    }

    [Fact]
    public void PingInviteLink_MatchesMacUrlAndTokenParsing()
    {
        Assert.Equal(
            "https://ping0min.vercel.app/invite/abc12345",
            PingInviteLink.ShareTextFor("abc12345", "https://ping0min.vercel.app"));
        Assert.Equal("abc12345", PingInviteLink.TokenFrom("https://ping0min.vercel.app/invite/abc12345"));
        Assert.Equal("abc12345", PingInviteLink.TokenFrom("ping://invite/abc12345"));
        Assert.Equal("abc12345", PingInviteLink.TokenFrom("https://example.com/join?token=abc12345"));
        Assert.Equal("path12345", PingInviteLink.TokenFrom("https://example.com/invite/path12345?token=query12345"));
        Assert.Equal("abc12345", PingInviteLink.TokenFrom("abc12345"));
        Assert.Null(PingInviteLink.TokenFrom("not valid"));
    }

    private sealed class RecordingSocialRpcClient : ISupabaseRpcClient
    {
        public List<(string Function, object Body)> Calls { get; } = [];

        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            Calls.Add((function, body ?? new { }));
            object result = function switch
            {
                "ping_create_invite_link" => new[]
                {
                    new InviteLink("token", "room-id", "Main", "Youngmin", DateTimeOffset.UtcNow.AddDays(7))
                },
                "ping_incoming_invitations" => new[]
                {
                    new Invitation("invite-id", "sender", "receiver", "room-id", "Sender", "Main", DateTimeOffset.UtcNow, DateTimeOffset.UtcNow.AddDays(7))
                },
                "ping_room_chat_messages" => new[]
                {
                    new ChatMessage
                    {
                        Id = "chat-id",
                        RoomId = "room-id",
                        SenderUid = "sender",
                        SenderNickname = "Sender",
                        Body = "hello"
                    }
                },
                "ping_unread_chat_counts" => new[]
                {
                    new UnreadChatCount("room-id", 1)
                },
                "ping_message_reactions" => new[]
                {
                    new MessageReaction(ReactionTargetKind.Video, "video-id", "+1", 1, true)
                },
                _ => new[] { Room() }
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }

        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            Calls.Add((function, body ?? new { }));
            object value = function == "ping_react" ? true : "id";
            return Task.FromResult((T)value);
        }

        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            Calls.Add((function, body ?? new { }));
            return Task.CompletedTask;
        }

        private static Room Room() =>
            new(
                Id: "room-id",
                Name: "Main",
                SearchableName: "main",
                OwnerUid: "sender",
                MemberUids: ["sender", "receiver"],
                MemberNicknames: new Dictionary<string, string>
                {
                    ["sender"] = "Sender",
                    ["receiver"] = "Receiver"
                },
                Status: RoomStatus.Open);
    }
}
