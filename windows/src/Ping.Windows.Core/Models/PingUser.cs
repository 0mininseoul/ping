using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Models;

public sealed record PingUser(
    [property: JsonPropertyName("id")] string? Id,
    [property: JsonPropertyName("nickname")] string Nickname,
    [property: JsonPropertyName("searchable_nickname")] string SearchableNickname,
    [property: JsonPropertyName("rooms")] IReadOnlyList<string> Rooms,
    [property: JsonPropertyName("last_used_room_id")] string? LastUsedRoomId,
    [property: JsonPropertyName("created_at")] DateTimeOffset? CreatedAt = null);
