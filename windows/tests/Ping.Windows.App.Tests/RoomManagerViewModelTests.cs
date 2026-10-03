using System.Text.Json;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class RoomManagerViewModelTests
{
    [Theory]
    [InlineData("join", "ping_join_room")]
    [InlineData("link", "ping_accept_invite_link")]
    [InlineData("invite", "ping_invite_user")]
    [InlineData("rename", "ping_rename_room")]
    [InlineData("leave", "ping_leave_room")]
    public async Task Confirmed_mutation_is_preserved_if_following_room_reload_fails(string action, string function)
    {
        var rpc = new RecordingRoomRpcClient { FailReload = true };
        var model = new RoomManagerViewModel(new(rpc), new(rpc), "민", currentUidProvider: () => "sender");
        var changes = 0; model.RoomsChanged += (_, _) => changes++;
        if (action is "rename" or "leave") { model.Rooms.Add(Room()); model.SelectedRoom = model.Rooms[0]; }
        switch (action)
        {
            case "join": model.SelectedSearchResult = Room(); await model.JoinSelectedSearchResultAsync(); break;
            case "link": await model.AcceptInviteLinkAsync("invite-token"); break;
            case "invite": await model.InviteUserAsync("receiver", "함께 이야기"); break;
            case "rename": await model.RenameSelectedRoomAsync("새 이름"); break;
            case "leave": await model.LeaveSelectedRoomAsync(); break;
        }
        Assert.Equal(1, changes);
        Assert.Single(rpc.Calls, call => call.Function == function);
        Assert.Contains("목록", model.StatusMessage);
        if (action == "leave") { Assert.Empty(model.Rooms); Assert.Null(model.SelectedRoom); }
        else { Assert.Equal("room-id", model.SelectedRoom?.Id); Assert.Single(model.Rooms); }
        if (action == "rename") Assert.Equal("새 이름", model.SelectedRoom?.Name);
    }

    [Fact]
    public async Task CreatedRoomIsRetainedWhenOnlyTheFollowingReloadFails()
    {
        var rpc = new RecordingRoomRpcClient { FailReload = true };
        var model = new RoomManagerViewModel(new RoomService(rpc), new InvitationService(rpc), "민");
        var changes = 0;
        model.RoomsChanged += (_, _) => changes++;
        await model.CreateRoomAsync("새 룸");
        Assert.Equal("room-id", Assert.Single(model.Rooms).Id);
        Assert.Equal("room-id", model.SelectedRoom?.Id);
        Assert.Equal(1, changes);
        Assert.Contains("목록", model.StatusMessage);
        Assert.Single(rpc.Calls, call => call.Function == "ping_create_room");
    }

    [Fact]
    public async Task Focus_newly_created_room_refreshes_stale_collection_before_invitation()
    {
        var rpc = new RecordingRoomRpcClient();
        var model = new RoomManagerViewModel(new RoomService(rpc), new InvitationService(rpc), "민지");
        var old = Room() with { Id = "old-room" };
        model.Rooms.Add(old); model.SelectedRoom = old;
        await model.FocusRoomAsync("room-id");
        Assert.Equal("room-id", model.SelectedRoom?.Id);
        Assert.Contains(rpc.Calls, call => call.Function == "ping_my_rooms");
    }

    [Fact]
    public async Task Missing_target_room_never_leaves_another_room_selected_for_invitation()
    {
        var rpc = new RecordingRoomRpcClient();
        var model = new RoomManagerViewModel(new RoomService(rpc), new InvitationService(rpc), "민지");
        model.Rooms.Add(Room()); model.SelectedRoom = model.Rooms[0];
        await model.FocusRoomAsync("deleted-room");
        Assert.Null(model.SelectedRoom);
    }

    [Fact]
    public async Task CreateInviteLinkCopiesTokenToClipboard()
    {
        var rpc = new RecordingRoomRpcClient();
        var clipboard = new RecordingClipboardWriter();
        var viewModel = new RoomManagerViewModel(
            new RoomService(rpc),
            new InvitationService(rpc),
            "Youngmin",
            clipboard,
            inviteLinkFormatter: token => PingInviteLink.ShareTextFor(token, "https://0minping.vercel.app"))
        {
            SelectedRoom = Room()
        };

        var token = await viewModel.CreateInviteLinkAsync();

        Assert.Equal("https://0minping.vercel.app/invite/invite-token", token);
        Assert.Equal("https://0minping.vercel.app/invite/invite-token", clipboard.Text);
        Assert.Equal("초대 링크를 복사했어요.", viewModel.StatusMessage);
    }

    [Fact]
    public async Task SearchUsersFiltersSelfAndInvitesSelectedUser()
    {
        var rpc = new RecordingRoomRpcClient();
        var viewModel = new RoomManagerViewModel(
            new RoomService(rpc),
            new InvitationService(rpc),
            "Youngmin",
            userService: new UserService(rpc),
            currentUidProvider: () => "sender")
        {
            SelectedRoom = Room()
        };

        await viewModel.SearchUsersAsync("  rec ");

        var user = Assert.Single(viewModel.UserSearchResults);
        Assert.Equal("Receiver", user.Nickname);
        Assert.Equal("초대할 사람을 선택하세요.", viewModel.StatusMessage);

        viewModel.SelectedUserSearchResult = user;
        await viewModel.InviteSelectedUserAsync("Fallback");

        Assert.Equal("초대를 보냈어요.", viewModel.StatusMessage);
        Assert.Contains(rpc.Calls, call =>
            call.Function == "ping_search_profiles"
            && JsonSerializer.Serialize(call.Body, JsonOptions.Supabase) == """{"search_prefix":"rec"}""");
        Assert.Contains(rpc.Calls, call =>
            call.Function == "ping_send_invitation"
            && JsonSerializer.Serialize(call.Body, JsonOptions.Supabase).Contains("\"to_uid\":\"receiver\"", StringComparison.Ordinal));
    }

    [Fact]
    public async Task ApplyProfileNicknameUsesLatestNicknameForFutureRoomActions()
    {
        var rpc = new RecordingRoomRpcClient();
        var viewModel = new RoomManagerViewModel(
            new RoomService(rpc),
            new InvitationService(rpc),
            "Old Name")
        {
            SelectedRoom = Room()
        };

        viewModel.ApplyProfileNickname("  New\tName\n  ");
        await viewModel.InviteUserAsync("receiver", "Fallback");
        await viewModel.AcceptInviteLinkAsync("https://0minping.vercel.app/invite/token-123");

        Assert.Contains(rpc.Calls, call =>
            call.Function == "ping_send_invitation"
            && JsonSerializer.Serialize(call.Body, JsonOptions.Supabase).Contains("\"from_nickname\":\"New Name\"", StringComparison.Ordinal));
        Assert.Contains(rpc.Calls, call =>
            call.Function == "ping_accept_invite_link"
            && JsonSerializer.Serialize(call.Body, JsonOptions.Supabase).Contains("\"nickname_text\":\"New Name\"", StringComparison.Ordinal));
    }

    [Fact]
    public async Task SearchRoomsClearsStaleSelectionWhenNoResults()
    {
        var rpc = new RecordingRoomRpcClient
        {
            SearchRoomResults = []
        };
        var viewModel = new RoomManagerViewModel(
            new RoomService(rpc),
            new InvitationService(rpc),
            "Youngmin")
        {
            SelectedSearchResult = Room("stale-room", "Stale")
        };

        await viewModel.SearchRoomsAsync("missing");
        await viewModel.JoinSelectedSearchResultAsync();

        Assert.Null(viewModel.SelectedSearchResult);
        Assert.Empty(viewModel.SearchResults);
        Assert.DoesNotContain(rpc.Calls, call => call.Function == "ping_join_room");
    }

    [Fact]
    public async Task RejectInvitationClearsStaleSelectedInvitation()
    {
        var rpc = new RecordingRoomRpcClient();
        rpc.IncomingInvitations.Add(Invitation("invite-id"));
        var viewModel = new RoomManagerViewModel(
            new RoomService(rpc),
            new InvitationService(rpc),
            "Youngmin")
        {
            SelectedInvitation = Invitation("invite-id")
        };

        await viewModel.RejectSelectedInvitationAsync();

        Assert.Null(viewModel.SelectedInvitation);
        Assert.Empty(viewModel.Invitations);
        Assert.Contains(rpc.Calls, call =>
            call.Function == "ping_reject_invitation"
            && JsonSerializer.Serialize(call.Body, JsonOptions.Supabase) == """{"invitation_uuid":"invite-id"}""");
    }

    private static Room Room(string id = "room-id", string name = "Main") =>
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

    private static Invitation Invitation(string id) =>
        new(
            Id: id,
            FromUid: "sender",
            ToUid: "receiver",
            RoomId: "room-id",
            FromNickname: "Sender",
            RoomName: "Main",
            CreatedAt: DateTimeOffset.UtcNow,
            ExpiresAt: DateTimeOffset.UtcNow.AddDays(7));

    private sealed class RecordingClipboardWriter : IClipboardWriter
    {
        public string? Text { get; private set; }

        public Task<bool> TrySetTextAsync(string text, CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            Text = text;
            return Task.FromResult(true);
        }
    }

    private sealed class RecordingRoomRpcClient : ISupabaseRpcClient
    {
        public bool FailReload { get; init; }
        public List<(string Function, object Body)> Calls { get; } = [];

        public IReadOnlyList<Room> SearchRoomResults { get; init; } = [Room()];

        public List<Invitation> IncomingInvitations { get; } = [];

        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(
            string function,
            object? body = null,
            CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            Calls.Add((function, body ?? new { }));
            if (function == "ping_my_rooms" && FailReload) throw new InvalidOperationException("목록 연결 실패");
            object result = function switch
            {
                "ping_create_invite_link" => new[]
                {
                    new InviteLink("invite-token", "room-id", "Main", "Youngmin", DateTimeOffset.UtcNow.AddDays(7))
                },
                "ping_incoming_invitations" => IncomingInvitations.ToArray(),
                "ping_search_open_rooms" => SearchRoomResults,
                "ping_search_profiles" => new[]
                {
                    new PingUser("sender", "Youngmin", "youngmin", [], null),
                    new PingUser("receiver", "Receiver", "receiver", [], null)
                },
                _ => new[] { Room() }
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }

        public Task<T> RpcValueAsync<T>(
            string function,
            object? body = null,
            CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            Calls.Add((function, body ?? new { }));
            return Task.FromResult((T)(object)"id");
        }

        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            Calls.Add((function, body ?? new { }));
            if (function == "ping_reject_invitation")
            {
                IncomingInvitations.Clear();
            }

            return Task.CompletedTask;
        }
    }
}
