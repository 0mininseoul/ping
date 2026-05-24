using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Models;

public enum RoomStatus
{
    Open,
    Full
}

public sealed record Room(
    [property: JsonPropertyName("id")] string? Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("searchable_name")] string SearchableName,
    [property: JsonPropertyName("owner_uid")] string OwnerUid,
    [property: JsonPropertyName("member_uids")] IReadOnlyList<string> MemberUids,
    [property: JsonPropertyName("member_nicknames")] IReadOnlyDictionary<string, string> MemberNicknames,
    [property: JsonPropertyName("status")] RoomStatus Status,
    [property: JsonPropertyName("created_at")] DateTimeOffset? CreatedAt = null);
