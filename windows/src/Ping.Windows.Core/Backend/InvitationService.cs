using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public sealed class InvitationService(ISupabaseRpcClient client)
{
    public Task<string> SendAsync(
        string toUid,
        string roomId,
        string fromNickname,
        string roomName,
        CancellationToken cancellationToken = default) =>
        client.RpcValueAsync<string>(
            "ping_send_invitation",
            new SendInvitationRpcBody(toUid, roomId, fromNickname, RoomName.Normalize(roomName)),
            cancellationToken);

    public async Task<Room> InviteUserAsync(
        string targetUid,
        string inviterNickname,
        string roomName,
        CancellationToken cancellationToken = default)
    {
        var normalized = RoomName.Normalize(roomName);
        var rooms = await client.RpcArrayAsync<Room>(
            "ping_invite_user",
            new InviteUserRpcBody(
                targetUid,
                inviterNickname,
                normalized,
                SearchableText.Normalize(normalized)),
            cancellationToken).ConfigureAwait(false);
        return rooms.FirstOrDefault()
            ?? throw new InvalidOperationException("Invite-user RPC returned no room.");
    }

    public Task<IReadOnlyList<Invitation>> IncomingAsync(CancellationToken cancellationToken = default) =>
        client.RpcArrayAsync<Invitation>("ping_incoming_invitations", cancellationToken: cancellationToken);

    public Task AcceptAsync(
        string invitationId,
        string nickname,
        CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync(
            "ping_accept_invitation",
            new AcceptInvitationRpcBody(invitationId, nickname),
            cancellationToken);

    public Task RejectAsync(string invitationId, CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync(
            "ping_reject_invitation",
            new InvitationIdRpcBody(invitationId),
            cancellationToken);

    public async Task<InviteLink> CreateInviteLinkAsync(
        string roomId,
        CancellationToken cancellationToken = default)
    {
        var links = await client.RpcArrayAsync<InviteLink>(
            "ping_create_invite_link",
            new RoomIdRpcBody(roomId),
            cancellationToken).ConfigureAwait(false);
        return links.FirstOrDefault()
            ?? throw new InvalidOperationException("Invite-link RPC returned no link.");
    }

    public async Task<Room> AcceptInviteLinkAsync(
        string token,
        string nickname,
        CancellationToken cancellationToken = default)
    {
        var rooms = await client.RpcArrayAsync<Room>(
            "ping_accept_invite_link",
            new AcceptInviteLinkRpcBody(token, nickname),
            cancellationToken).ConfigureAwait(false);
        return rooms.FirstOrDefault()
            ?? throw new InvalidOperationException("Accept invite-link RPC returned no room.");
    }
}

public sealed record SendInvitationRpcBody(
    [property: JsonPropertyName("to_uid")] string ToUid,
    [property: JsonPropertyName("room_uuid")] string RoomUuid,
    [property: JsonPropertyName("from_nickname")] string FromNickname,
    [property: JsonPropertyName("room_name_text")] string RoomNameText);

public sealed record InviteUserRpcBody(
    [property: JsonPropertyName("target_uid")] string TargetUid,
    [property: JsonPropertyName("inviter_nickname_text")] string InviterNicknameText,
    [property: JsonPropertyName("room_name_text")] string RoomNameText,
    [property: JsonPropertyName("searchable_room_name")] string SearchableRoomName);

public sealed record AcceptInvitationRpcBody(
    [property: JsonPropertyName("invitation_uuid")] string InvitationUuid,
    [property: JsonPropertyName("nickname_text")] string NicknameText);

public sealed record InvitationIdRpcBody(
    [property: JsonPropertyName("invitation_uuid")] string InvitationUuid);

public sealed record AcceptInviteLinkRpcBody(
    [property: JsonPropertyName("invite_token")] string InviteToken,
    [property: JsonPropertyName("nickname_text")] string NicknameText);
