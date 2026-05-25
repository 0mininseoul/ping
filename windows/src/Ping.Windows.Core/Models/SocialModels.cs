using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Models;

public sealed record Invitation(
    [property: JsonPropertyName("id")] string? Id,
    [property: JsonPropertyName("from_uid")] string FromUid,
    [property: JsonPropertyName("to_uid")] string ToUid,
    [property: JsonPropertyName("room_id")] string RoomId,
    [property: JsonPropertyName("from_nickname")] string FromNickname,
    [property: JsonPropertyName("room_name")] string RoomName,
    [property: JsonPropertyName("created_at")] DateTimeOffset? CreatedAt,
    [property: JsonPropertyName("expires_at")] DateTimeOffset ExpiresAt);

public sealed record InviteLink(
    [property: JsonPropertyName("token")] string Token,
    [property: JsonPropertyName("room_id")] string RoomId,
    [property: JsonPropertyName("room_name")] string RoomName,
    [property: JsonPropertyName("inviter_nickname")] string InviterNickname,
    [property: JsonPropertyName("expires_at")] DateTimeOffset ExpiresAt);

public sealed record ChatMessage
{
    [JsonPropertyName("id")]
    public string? Id { get; init; }

    [JsonPropertyName("room_id")]
    public required string RoomId { get; init; }

    [JsonPropertyName("sender_uid")]
    public required string SenderUid { get; init; }

    [JsonPropertyName("sender_nickname")]
    public required string SenderNickname { get; init; }

    [JsonPropertyName("body")]
    public string Body { get; init; } = string.Empty;

    [JsonPropertyName("reply_to_chat_id")]
    public string? ReplyToChatId { get; init; }

    [JsonPropertyName("reply_to_video_id")]
    public string? ReplyToVideoId { get; init; }

    [JsonPropertyName("media_path")]
    public string? MediaPath { get; init; }

    [JsonPropertyName("media_mime_type")]
    public string? MediaMimeType { get; init; }

    [JsonPropertyName("media_width")]
    public int? MediaWidth { get; init; }

    [JsonPropertyName("media_height")]
    public int? MediaHeight { get; init; }

    [JsonPropertyName("media_file_name")]
    public string? MediaFileName { get; init; }

    [JsonPropertyName("created_at")]
    public DateTimeOffset? CreatedAt { get; init; }
}

public enum ReactionTargetKind
{
    Chat,
    Video
}

public sealed record MessageReaction(
    [property: JsonPropertyName("target_kind")] ReactionTargetKind TargetKind,
    [property: JsonPropertyName("target_id")] string TargetId,
    [property: JsonPropertyName("emoji")] string Emoji,
    [property: JsonPropertyName("total_count")] int TotalCount,
    [property: JsonPropertyName("my_reacted")] bool MyReacted);

public sealed record UnreadChatCount(
    [property: JsonPropertyName("room_id")] string RoomId,
    [property: JsonPropertyName("unread_count")] int UnreadCount);
