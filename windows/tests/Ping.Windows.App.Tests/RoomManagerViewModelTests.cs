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
            inviteLinkFormatter: token => PingInviteLink.ShareTextFor(token, "https://ping0min.vercel.app"))
        {
            SelectedRoom = Room()
        };

        var token = await viewModel.CreateInviteLinkAsync();

        Assert.Equal("https://ping0min.vercel.app/invite/invite-token", token);
        Assert.Equal("https://ping0min.vercel.app/invite/invite-token", clipboard.Text);
        Assert.Equal("Invite link copied to clipboard.", viewModel.StatusMessage);
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
        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(
            string function,
            object? body = null,
            CancellationToken cancellationToken = default)
        {
            _ = body;
            _ = cancellationToken;
            object result = function == "ping_create_invite_link"
                ? new[]
                {
                    new InviteLink("invite-token", "room-id", "Main", "Youngmin", DateTimeOffset.UtcNow.AddDays(7))
                }
                : new[] { Room() };
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
            return Task.FromResult((T)(object)"id");
        }

        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            _ = function;
            _ = body;
            _ = cancellationToken;
            return Task.CompletedTask;
        }
    }
}
