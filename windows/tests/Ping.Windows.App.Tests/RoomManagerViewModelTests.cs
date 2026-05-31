using System.Text.Json;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class RoomManagerViewModelTests
{
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
        Assert.Equal("Invite link copied to clipboard.", viewModel.StatusMessage);
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
        Assert.Equal("Select a user to invite.", viewModel.StatusMessage);

        viewModel.SelectedUserSearchResult = user;
        await viewModel.InviteSelectedUserAsync("Fallback");

        Assert.Equal("Invitation sent.", viewModel.StatusMessage);
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
