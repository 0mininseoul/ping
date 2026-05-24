using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public sealed class UserService(ISupabaseRpcClient client)
{
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

public sealed record GetProfileRpcBody(
    [property: JsonPropertyName("target_uid")] string TargetUid);

public sealed record UpdateLastUsedRoomRpcBody(
    [property: JsonPropertyName("room_uuid")] string RoomUuid);
