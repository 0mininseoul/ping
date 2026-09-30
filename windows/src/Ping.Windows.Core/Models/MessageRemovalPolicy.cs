namespace Ping.Windows.Core.Models;

public enum MessageRemovalAction { None, Delete, Hide }

public static class MessageRemovalPolicy
{
    public static readonly TimeSpan SenderWindow = TimeSpan.FromMinutes(5);

    public static MessageRemovalAction ForVideo(string senderUid, string receiverUid,
        DateTimeOffset? createdAt, string? currentUid, DateTimeOffset now)
    {
        if (string.IsNullOrWhiteSpace(currentUid)) return MessageRemovalAction.None;
        if (senderUid == currentUid)
            return CanDeleteChat(senderUid, createdAt, currentUid, now) ? MessageRemovalAction.Delete : MessageRemovalAction.None;
        return receiverUid == currentUid ? MessageRemovalAction.Hide : MessageRemovalAction.None;
    }

    public static bool CanDeleteChat(string senderUid, DateTimeOffset? createdAt, string? currentUid, DateTimeOffset now) =>
        !string.IsNullOrWhiteSpace(currentUid) && senderUid == currentUid && createdAt is { } sentAt
        && sentAt <= now && now - sentAt <= SenderWindow;
}
