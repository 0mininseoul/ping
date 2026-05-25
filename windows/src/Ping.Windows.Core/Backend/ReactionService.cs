using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public sealed class ReactionService(ISupabaseRpcClient client)
{
    public Task<bool> ToggleAsync(
        ReactionTargetKind targetKind,
        string targetId,
        string emoji,
        CancellationToken cancellationToken = default) =>
        client.RpcValueAsync<bool>(
            "ping_react",
            new ToggleReactionRpcBody(targetKind.ToWireValue(), targetId, emoji),
            cancellationToken);

    public Task<IReadOnlyList<MessageReaction>> ReactionsAsync(
        IReadOnlyCollection<string> chatIds,
        IReadOnlyCollection<string> videoIds,
        CancellationToken cancellationToken = default) =>
        client.RpcArrayAsync<MessageReaction>(
            "ping_message_reactions",
            new MessageReactionsRpcBody(chatIds, videoIds),
            cancellationToken);
}

public static class ReactionTargetKindWire
{
    public static string ToWireValue(this ReactionTargetKind kind) =>
        kind switch
        {
            ReactionTargetKind.Chat => "chat",
            ReactionTargetKind.Video => "video",
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unknown reaction target kind.")
        };
}

public sealed record ToggleReactionRpcBody(
    [property: JsonPropertyName("target_kind")] string TargetKind,
    [property: JsonPropertyName("target_uuid")] string TargetUuid,
    [property: JsonPropertyName("emoji_text")] string EmojiText);

public sealed record MessageReactionsRpcBody(
    [property: JsonPropertyName("chat_ids")] IReadOnlyCollection<string> ChatIds,
    [property: JsonPropertyName("video_ids")] IReadOnlyCollection<string> VideoIds);
