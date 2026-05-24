using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public sealed class RoomService(ISupabaseRpcClient client)
{
    public async Task<Room> CreateRoomAsync(
        string roomName,
        string ownerNickname,
        CancellationToken cancellationToken = default)
    {
        var normalized = RoomName.Normalize(roomName);
        var rooms = await client.RpcArrayAsync<Room>(
            "ping_create_room",
            new CreateRoomRpcBody(normalized, SearchableText.Normalize(normalized), ownerNickname),
            cancellationToken).ConfigureAwait(false);
        return rooms.FirstOrDefault()
            ?? throw new InvalidOperationException("Room creation returned no room.");
    }

    public Task<IReadOnlyList<Room>> MyRoomsAsync(CancellationToken cancellationToken = default) =>
        client.RpcArrayAsync<Room>("ping_my_rooms", cancellationToken: cancellationToken);

    public Task<IReadOnlyList<Room>> SearchOpenRoomsAsync(
        string prefix,
        CancellationToken cancellationToken = default) =>
        client.RpcArrayAsync<Room>(
            "ping_search_open_rooms",
            new SearchOpenRoomsRpcBody(SearchableText.Normalize(prefix)),
            cancellationToken);

    public Task JoinRoomAsync(string roomId, string nickname, CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync(
            "ping_join_room",
            new JoinRoomRpcBody(roomId, nickname),
            cancellationToken);

    public Task LeaveRoomAsync(string roomId, CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync("ping_leave_room", new RoomIdRpcBody(roomId), cancellationToken);

    public Task RenameRoomAsync(string roomId, string newName, CancellationToken cancellationToken = default)
    {
        var normalized = RoomName.Normalize(newName);
        return client.RpcVoidAsync(
            "ping_rename_room",
            new RenameRoomRpcBody(roomId, normalized, SearchableText.Normalize(normalized)),
            cancellationToken);
    }
}

public static class SearchableText
{
    public static string Normalize(string value) =>
        string.Join(
            " ",
            (value ?? string.Empty)
                .Trim()
                .ToLowerInvariant()
                .Split(' ', StringSplitOptions.RemoveEmptyEntries));
}

public static class RoomName
{
    public static string Normalize(string value)
    {
        var normalized = string.Join(
            " ",
            (value ?? string.Empty).Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries));
        if (normalized.Length is < 1 or > 48)
        {
            throw new ArgumentException("Room name must be 1-48 characters after trimming.", nameof(value));
        }

        return normalized;
    }
}

public sealed record CreateRoomRpcBody(
    [property: JsonPropertyName("room_name")] string RoomName,
    [property: JsonPropertyName("searchable_room_name")] string SearchableRoomName,
    [property: JsonPropertyName("owner_nickname")] string OwnerNickname);

public sealed record SearchOpenRoomsRpcBody(
    [property: JsonPropertyName("search_prefix")] string SearchPrefix);

public sealed record JoinRoomRpcBody(
    [property: JsonPropertyName("room_uuid")] string RoomUuid,
    [property: JsonPropertyName("nickname_text")] string NicknameText);

public sealed record RoomIdRpcBody(
    [property: JsonPropertyName("room_uuid")] string RoomUuid);

public sealed record RenameRoomRpcBody(
    [property: JsonPropertyName("room_uuid")] string RoomUuid,
    [property: JsonPropertyName("new_name")] string NewName,
    [property: JsonPropertyName("new_searchable_name")] string NewSearchableName);
