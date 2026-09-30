using System.Text.Json;

namespace Ping.Windows.Core.Realtime;

public sealed record RealtimeFilter(string Event, string Schema, string Table, string Filter);
public sealed record RealtimeChannel(string Topic, string? RoomId, IReadOnlyList<RealtimeFilter> Filters);
public enum RealtimeChangeKind { Chat, Reaction, IncomingVideo }
public sealed record RealtimeChange(RealtimeChangeKind Kind, string? RoomId, string? ItemId, string Operation);
public sealed record RealtimeFrame(string Event, string Topic, string? Reference, JsonElement Payload)
{
    public override string ToString() => Event;
}
public sealed class RealtimeProtocolException(string message = "Invalid Realtime frame.") : Exception(message);

public static class RealtimeProtocol
{
    public static Uri SocketEndpoint(Uri projectUrl, string anonKey)
    {
        if (projectUrl.Scheme is not ("https" or "http")) throw new ArgumentException("Realtime requires an HTTP project endpoint.");
        var endpoint = new UriBuilder(projectUrl)
        {
            Scheme = projectUrl.Scheme == "https" ? "wss" : "ws",
            Path = projectUrl.AbsolutePath.TrimEnd('/') + "/realtime/v1/websocket",
            Query = "apikey=" + Uri.EscapeDataString(anonKey) + "&vsn=1.0.0"
        };
        return endpoint.Uri;
    }

    public static IReadOnlyList<RealtimeChannel> Channels(string uid, IReadOnlyCollection<string> roomIds)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uid);
        var channels = roomIds.Where(id => !string.IsNullOrWhiteSpace(id)).Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal)
            .Select(id => new RealtimeChannel("realtime:chat-room-" + id, id,
                [new("*", "public", "chat_messages", "room_id=eq." + id), new("*", "public", "message_reactions", "room_id=eq." + id)]))
            .ToList();
        channels.Add(new("realtime:incoming-video-" + uid, null, [new("INSERT", "public", "messages", "receiver_uid=eq." + uid)]));
        return channels;
    }

    public static string Join(RealtimeChannel channel, string token, string reference) => Encode(channel.Topic, "phx_join", new
    {
        config = new
        {
            broadcast = new { ack = false, self = false }, presence = new { enabled = false }, @private = false,
            postgres_changes = channel.Filters.Select(filter => new { @event = filter.Event, schema = filter.Schema, table = filter.Table, filter = filter.Filter })
        },
        access_token = token
    }, reference, reference);

    public static string Encode(string topic, string eventName, object payload, string reference, string? joinReference = null) =>
        JsonSerializer.Serialize(new { topic, @event = eventName, payload, @ref = reference, join_ref = joinReference });

    public static RealtimeFrame Decode(string text)
    {
        try
        {
            using var document = JsonDocument.Parse(text);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || String(root, "event") is not { Length: > 0 } eventName
                || String(root, "topic") is not { Length: > 0 } topic || !root.TryGetProperty("payload", out var payload)
                || payload.ValueKind != JsonValueKind.Object) throw new RealtimeProtocolException();
            return new(eventName, topic, String(root, "ref"), payload.Clone());
        }
        catch (JsonException) { throw new RealtimeProtocolException(); }
    }

    public static bool JoinAccepted(RealtimeFrame frame, RealtimeChannel channel)
    {
        if (String(frame.Payload, "status") != "ok" || !frame.Payload.TryGetProperty("response", out var response)
            || response.ValueKind != JsonValueKind.Object || !response.TryGetProperty("postgres_changes", out var changes)
            || changes.ValueKind != JsonValueKind.Array || changes.GetArrayLength() != channel.Filters.Count) return false;
        return channel.Filters.All(filter => changes.EnumerateArray().Any(change =>
            String(change, "schema") == filter.Schema && String(change, "table") == filter.Table && String(change, "event") == filter.Event
            && change.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.Number));
    }

    public static RealtimeChange? Change(RealtimeFrame frame, RealtimeChannel channel)
    {
        if (frame.Event != "postgres_changes" || frame.Topic != channel.Topic
            || !frame.Payload.TryGetProperty("data", out var data) || data.ValueKind != JsonValueKind.Object
            || String(data, "schema") != "public" || String(data, "table") is not { } table
            || !channel.Filters.Any(filter => filter.Table == table) || String(data, "type") is not { } operation) return null;
        if (operation is not ("INSERT" or "UPDATE" or "DELETE")) return null;
        if (data.TryGetProperty("errors", out var errors) && errors.ValueKind != JsonValueKind.Null) throw new RealtimeProtocolException("Realtime change requires reconciliation.");
        var recordName = operation == "DELETE" ? "old_record" : "record";
        data.TryGetProperty(recordName, out var record);
        var roomId = String(record, "room_id") ?? channel.RoomId;
        if (channel.RoomId is not null && roomId != channel.RoomId) return null;
        var kind = table switch { "chat_messages" => RealtimeChangeKind.Chat, "message_reactions" => RealtimeChangeKind.Reaction, _ => RealtimeChangeKind.IncomingVideo };
        return new(kind, roomId, String(record, "id"), operation);
    }

    public static string? String(JsonElement element, string name) => element.ValueKind == JsonValueKind.Object
        && element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
