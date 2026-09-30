using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Capture;

public enum AutoFaceReplyDecision
{
    Record, NotLive, InvalidMessage, AutoReplyMessage, AlreadyReplied, MissingTimestamp, StaleMessage,
    DisplayAsleep, CameraUnavailable, CameraBusy, StaleInFlight, InterruptedBySleep
}

public static class AutoFaceReplyPolicy
{
    public static readonly TimeSpan FreshnessWindow = TimeSpan.FromSeconds(60);
    public static readonly TimeSpan ClipDuration = TimeSpan.FromSeconds(3);

    public static AutoFaceReplyDecision Decide(VideoMessage message, string currentUid, IncomingArrivalSource source,
        DateTimeOffset appStartedAt, DateTimeOffset now, bool alreadyReplied, bool isDisplayAsleep,
        bool isCameraAuthorized, bool isCameraBusy)
    {
        if (source != IncomingArrivalSource.Live) return AutoFaceReplyDecision.NotLive;
        if (message.IsAutoReply) return AutoFaceReplyDecision.AutoReplyMessage;
        if (string.IsNullOrWhiteSpace(currentUid) || string.IsNullOrWhiteSpace(message.Id)
            || string.IsNullOrWhiteSpace(message.RoomId) || string.IsNullOrWhiteSpace(message.SenderUid)
            || message.SenderUid == currentUid || message.ReceiverUid != currentUid || message.ExpiresAt <= now)
            return AutoFaceReplyDecision.InvalidMessage;
        if (alreadyReplied) return AutoFaceReplyDecision.AlreadyReplied;
        if (message.CreatedAt is not { } created) return AutoFaceReplyDecision.MissingTimestamp;
        if (created <= appStartedAt || !IsFresh(created, now)) return AutoFaceReplyDecision.StaleMessage;
        if (isDisplayAsleep) return AutoFaceReplyDecision.DisplayAsleep;
        if (!isCameraAuthorized) return AutoFaceReplyDecision.CameraUnavailable;
        if (isCameraBusy) return AutoFaceReplyDecision.CameraBusy;
        return AutoFaceReplyDecision.Record;
    }

    public static AutoFaceReplyDecision Recheck(VideoMessage message, DateTimeOffset now, bool interruptedBySleep)
    {
        if (interruptedBySleep) return AutoFaceReplyDecision.InterruptedBySleep;
        return message.CreatedAt is { } created && IsFresh(created, now) && message.ExpiresAt > now
            ? AutoFaceReplyDecision.Record : AutoFaceReplyDecision.StaleInFlight;
    }

    private static bool IsFresh(DateTimeOffset created, DateTimeOffset now) =>
        now - created >= TimeSpan.Zero && now - created <= FreshnessWindow;
}
