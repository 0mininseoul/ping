using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Models;

public enum MessageStatus
{
    Uploaded,
    Seen
}

public sealed record VideoMessage
{
    [JsonPropertyName("id")]
    public string? Id { get; init; }

    [JsonPropertyName("room_id")]
    public required string RoomId { get; init; }

    [JsonPropertyName("sender_uid")]
    public required string SenderUid { get; init; }

    [JsonPropertyName("receiver_uid")]
    public required string ReceiverUid { get; init; }

    [JsonPropertyName("sender_nickname")]
    public required string SenderNickname { get; init; }

    [JsonPropertyName("video_id")]
    public required string VideoId { get; init; }

    [JsonPropertyName("video_url")]
    public required string VideoUrl { get; init; }

    [JsonPropertyName("duration_ms")]
    public required int DurationMs { get; init; }

    [JsonPropertyName("mirror_position")]
    public required MirrorPosition MirrorPosition { get; init; }

    [JsonPropertyName("status")]
    public required MessageStatus Status { get; init; }

    [JsonPropertyName("created_at")]
    public DateTimeOffset? CreatedAt { get; init; }

    [JsonPropertyName("expires_at")]
    public required DateTimeOffset ExpiresAt { get; init; }

    [JsonPropertyName("capture_mode")]
    public CaptureMode CaptureMode { get; init; } = CaptureMode.FaceOnly;

    [JsonPropertyName("aspect_ratio")]
    public double? AspectRatio { get; init; }

    [JsonPropertyName("allows_local_save")]
    public bool AllowsLocalSave { get; init; }

    public bool CanBeSavedLocally(string? uid) => SenderUid == uid || AllowsLocalSave;
}
