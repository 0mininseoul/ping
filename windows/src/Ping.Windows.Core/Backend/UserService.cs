using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public sealed class UserService(ISupabaseRpcClient client)
{
    public async Task<PingUser?> UpsertAsync(string nickname, CancellationToken cancellationToken = default)
    {
        var normalized = string.Join(" ", (nickname ?? string.Empty).Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries));
        if (string.IsNullOrWhiteSpace(normalized))
        {
            throw new ArgumentException("Nickname is required.", nameof(nickname));
        }

        var users = await client.RpcArrayAsync<PingUser>(
            "ping_upsert_profile",
            new UpsertProfileRpcBody(normalized, SearchableText.Normalize(normalized)),
            cancellationToken).ConfigureAwait(false);
        return users.FirstOrDefault();
    }

    public async Task<PingUser?> GetAsync(string uid, CancellationToken cancellationToken = default)
    {
        var users = await client.RpcArrayAsync<PingUser>(
            "ping_get_profile",
            new GetProfileRpcBody(uid),
            cancellationToken).ConfigureAwait(false);
        return users.FirstOrDefault();
    }

    public Task UpdateLastUsedRoomAsync(string roomId, CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync(
            "ping_update_last_used_room",
            new UpdateLastUsedRoomRpcBody(roomId),
            cancellationToken);
}

public sealed record UpsertProfileRpcBody(
    [property: JsonPropertyName("nickname_text")] string NicknameText,
    [property: JsonPropertyName("searchable_nickname_text")] string SearchableNicknameText);

public sealed record GetProfileRpcBody(
    [property: JsonPropertyName("target_uid")] string TargetUid);

public sealed record UpdateLastUsedRoomRpcBody(
    [property: JsonPropertyName("room_uuid")] string RoomUuid);
