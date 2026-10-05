using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Incoming;

public enum IncomingArrivalSource { Live, StartupCatchUp, ReconnectCatchUp, NotificationClick, HistoryReplay }

public sealed record IncomingVideoDecision(bool IsEligible, bool ShouldNotify, bool ShouldAutoPlay, bool IsExplicitReplay = false)
{
    public bool ShouldOpenPlayback => IsEligible && (ShouldAutoPlay || IsExplicitReplay);
}

public static class IncomingArrivalPolicy
{
    public static readonly TimeSpan AutoPlayFreshness = TimeSpan.FromSeconds(60);
    public static readonly TimeSpan MaximumFutureClockSkew = TimeSpan.FromSeconds(30);

    public static IncomingVideoDecision Decide(VideoMessage message, string currentUid, IncomingArrivalSource source,
        DateTimeOffset appStartedAt, DateTimeOffset now, bool autoPlayEnabled)
    {
        var explicitReplay = source is IncomingArrivalSource.NotificationClick or IncomingArrivalSource.HistoryReplay;
        if (string.IsNullOrWhiteSpace(currentUid) || string.IsNullOrWhiteSpace(message.Id)
            || message.CreatedAt is not { } created || message.ExpiresAt <= now
            || created > now + MaximumFutureClockSkew
            || (source != IncomingArrivalSource.HistoryReplay && message.ReceiverUid != currentUid))
            return new(false, false, false);

        var age = now - created;
        var autoPlay = source == IncomingArrivalSource.Live && autoPlayEnabled && message.SenderUid != currentUid
            && created > appStartedAt - MaximumFutureClockSkew && age >= TimeSpan.Zero && age <= AutoPlayFreshness;
        return new(true, !explicitReplay, autoPlay, explicitReplay);
    }
}
