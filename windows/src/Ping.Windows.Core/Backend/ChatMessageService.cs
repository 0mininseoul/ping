using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public sealed class ChatMessageService(ISupabaseRpcClient client)
{
    public Task<IReadOnlyList<ChatMessage>> RoomChatMessagesAsync(
        string roomId,
        DateTimeOffset? beforeTimestamp = null,
        int limit = 50,
        CancellationToken cancellationToken = default) =>
        client.RpcArrayAsync<ChatMessage>(
            "ping_room_chat_messages",
            new RoomChatMessagesRpcBody(roomId, beforeTimestamp, limit),
            cancellationToken);

    public Task<string> SendChatAsync(
        string roomId,
        string body,
        string? replyToChatId = null,
        string? replyToVideoId = null,
        string? messageId = null,
        ChatMediaPayload? media = null,
        CancellationToken cancellationToken = default)
    {
        var rpcBody = new Dictionary<string, object?>
        {
            ["room_uuid"] = roomId,
            ["body_text"] = body
        };
        AddIfPresent(rpcBody, "reply_chat_uuid", replyToChatId);
        AddIfPresent(rpcBody, "reply_video_uuid", replyToVideoId);
        AddIfPresent(rpcBody, "message_uuid", messageId);
        if (media is not null)
        {
            rpcBody["media_path_text"] = media.Path;
            rpcBody["media_mime_type_text"] = media.MimeType;
            AddIfPresent(rpcBody, "media_width_int", media.Width);
            AddIfPresent(rpcBody, "media_height_int", media.Height);
            AddIfPresent(rpcBody, "media_file_name_text", media.FileName);
        }

        return client.RpcValueAsync<string>("ping_send_chat", rpcBody, cancellationToken);
    }

    public Task DeleteChatAsync(string chatId, CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync("ping_delete_chat", new ChatIdRpcBody(chatId), cancellationToken);

    public Task MarkRoomReadAsync(string roomId, CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync("ping_mark_room_read", new RoomIdRpcBody(roomId), cancellationToken);

    public async Task<IReadOnlyDictionary<string, int>> UnreadChatCountsAsync(CancellationToken cancellationToken = default)
    {
        var rows = await client.RpcArrayAsync<UnreadChatCount>(
            "ping_unread_chat_counts",
            cancellationToken: cancellationToken).ConfigureAwait(false);
        return rows.ToDictionary(row => row.RoomId, row => row.UnreadCount, StringComparer.Ordinal);
    }

    private static void AddIfPresent(IDictionary<string, object?> body, string key, object? value)
    {
        if (value is not null)
        {
            body[key] = value;
        }
    }
}

public sealed record ChatMediaPayload(
    string Path,
    string MimeType,
    int? Width = null,
    int? Height = null,
    string? FileName = null);

public sealed record RoomChatMessagesRpcBody(
    [property: JsonPropertyName("room_uuid")] string RoomUuid,
    [property: JsonPropertyName("before_ts")] DateTimeOffset? BeforeTimestamp,
    [property: JsonPropertyName("page_limit")] int PageLimit);

public sealed record ChatIdRpcBody(
    [property: JsonPropertyName("chat_uuid")] string ChatUuid);
