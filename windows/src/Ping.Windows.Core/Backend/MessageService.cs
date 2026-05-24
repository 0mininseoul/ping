using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public sealed class MessageService(ISupabaseRpcClient client, IStorageService storage)
{
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
            .Order(StringComparer.Ordinal)
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
