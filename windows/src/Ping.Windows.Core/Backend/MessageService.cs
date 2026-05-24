using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public sealed class MessageService(ISupabaseRpcClient client, IStorageService storage)
{
    public async Task<IReadOnlyList<VideoMessage>> IncomingAsync(CancellationToken cancellationToken = default)
    {
        var messages = await client.RpcArrayAsync<VideoMessage>(
            "ping_incoming_messages",
            cancellationToken: cancellationToken).ConfigureAwait(false);
        return messages
            .OrderBy(MessageSortKey)
            .ThenBy(message => message.Id ?? string.Empty, StringComparer.Ordinal)
            .ToArray();
    }

    public async Task<VideoMessage?> GetAsync(string messageId, CancellationToken cancellationToken = default)
    {
        var messages = await client.RpcArrayAsync<VideoMessage>(
            "ping_get_message",
            new MessageIdRpcBody(messageId),
            cancellationToken).ConfigureAwait(false);
        return messages.FirstOrDefault();
    }

    public Task MarkSeenAsync(string messageId, CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync(
            "ping_mark_message_seen",
            new MessageIdRpcBody(messageId),
            cancellationToken);

    public Task<IReadOnlyList<VideoMessage>> RoomMessagesAsync(
        string roomId,
        DateTimeOffset? beforeTimestamp = null,
        int limit = 50,
        CancellationToken cancellationToken = default) =>
        client.RpcArrayAsync<VideoMessage>(
            "ping_room_messages",
            new RoomMessagesRpcBody(roomId, beforeTimestamp, limit),
            cancellationToken);

    public async Task SendAsync(SendVideoInput input, CancellationToken cancellationToken = default)
    {
        var sendableRooms = input.Rooms
            .Where(room => room.Id is not null && room.MemberUids.Contains(input.SenderUid) && room.MemberUids.Count >= 2)
            .ToArray();
        if (sendableRooms.Length == 0)
        {
            throw new InvalidOperationException("No recipients are available for this send.");
        }

        var sharedVideoId = input.SharedVideoId ?? Guid.NewGuid().ToString();
        var receiverUids = sendableRooms
            .SelectMany(room => room.MemberUids)
            .Where(uid => uid != input.SenderUid)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(uid => uid, StringComparer.Ordinal)
            .ToArray();
        var expiresAt = DateTimeOffset.UtcNow.AddDays(30);
        var videoStoragePath = await storage.UploadVideoAsync(
            input.LocalVideoPath,
            input.SenderUid,
            sharedVideoId,
            receiverUids,
            expiresAt,
            cancellationToken).ConfigureAwait(false);

        foreach (var room in sendableRooms)
        {
            foreach (var receiverUid in room.MemberUids.Where(uid => uid != input.SenderUid))
            {
                _ = await client.RpcValueAsync<string>(
                    "ping_create_message",
                    new CreateMessageRpcBody(
                        RoomUuid: room.Id!,
                        ReceiverUid: receiverUid,
                        SenderNicknameText: input.SenderNickname,
                        VideoIdText: sharedVideoId,
                        VideoUrlText: videoStoragePath,
                        XRatio: input.MirrorPosition.XRatio,
                        YRatio: input.MirrorPosition.YRatio,
                        CaptureModeText: input.CaptureMode.ToWireValue(),
                        AspectRatioValue: input.AspectRatio,
                        AllowsLocalSaveValue: input.AllowsLocalSave),
                    cancellationToken).ConfigureAwait(false);
            }
        }
    }

    private static DateTimeOffset MessageSortKey(VideoMessage message) =>
        message.CreatedAt ?? DateTimeOffset.MaxValue;
}

public sealed record SendVideoInput(
    IReadOnlyCollection<Room> Rooms,
    string LocalVideoPath,
    MirrorPosition MirrorPosition,
    string SenderUid,
    string SenderNickname,
    CaptureMode CaptureMode,
    double AspectRatio,
    bool AllowsLocalSave,
    string? SharedVideoId = null);

public sealed record CreateMessageRpcBody(
    [property: JsonPropertyName("room_uuid")] string RoomUuid,
    [property: JsonPropertyName("receiver_uid")] string ReceiverUid,
    [property: JsonPropertyName("sender_nickname_text")] string SenderNicknameText,
    [property: JsonPropertyName("video_id_text")] string VideoIdText,
    [property: JsonPropertyName("video_url_text")] string VideoUrlText,
    [property: JsonPropertyName("x_ratio")] double XRatio,
    [property: JsonPropertyName("y_ratio")] double YRatio,
    [property: JsonPropertyName("capture_mode_text")] string CaptureModeText,
    [property: JsonPropertyName("aspect_ratio_value")] double AspectRatioValue,
    [property: JsonPropertyName("allows_local_save_value")] bool AllowsLocalSaveValue);

public sealed record MessageIdRpcBody(
    [property: JsonPropertyName("message_uuid")] string MessageUuid);

public sealed record RoomMessagesRpcBody(
    [property: JsonPropertyName("room_uuid")] string RoomUuid,
    [property: JsonPropertyName("before_ts")] DateTimeOffset? BeforeTimestamp,
    [property: JsonPropertyName("page_limit")] int PageLimit);
