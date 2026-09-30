using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class AutoFaceReplyPolicyTests
{
    internal static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-30T09:00:00Z");
    internal static readonly DateTimeOffset Started = Now.AddMinutes(-5);

    [Fact]
    public void FreshLivePingRecords() => Assert.Equal(AutoFaceReplyDecision.Record, Decide(Video()));

    [Theory]
    [InlineData(IncomingArrivalSource.StartupCatchUp)]
    [InlineData(IncomingArrivalSource.ReconnectCatchUp)]
    [InlineData(IncomingArrivalSource.NotificationClick)]
    [InlineData(IncomingArrivalSource.HistoryReplay)]
    public void NonLiveSourcesNeverRecord(IncomingArrivalSource source) =>
        Assert.Equal(AutoFaceReplyDecision.NotLive, Decide(Video(), source));

    [Theory]
    [InlineData(60, AutoFaceReplyDecision.Record)]
    [InlineData(61, AutoFaceReplyDecision.StaleMessage)]
    [InlineData(-1, AutoFaceReplyDecision.StaleMessage)]
    [InlineData(300, AutoFaceReplyDecision.StaleMessage)]
    public void LaunchAndAgeBoundaries(int seconds, AutoFaceReplyDecision expected) =>
        Assert.Equal(expected, Decide(Video() with { CreatedAt = Now.AddSeconds(-seconds) }));

    [Fact]
    public void LoopsDuplicatesAndInvalidRecipientsCannotRecord()
    {
        Assert.Equal(AutoFaceReplyDecision.AutoReplyMessage, Decide(Video() with { IsAutoReply = true }));
        Assert.Equal(AutoFaceReplyDecision.AlreadyReplied, Decide(Video(), alreadyReplied: true));
        Assert.Equal(AutoFaceReplyDecision.InvalidMessage, Decide(Video() with { SenderUid = "me" }));
        Assert.Equal(AutoFaceReplyDecision.InvalidMessage, Decide(Video() with { ReceiverUid = "other" }));
        Assert.Equal(AutoFaceReplyDecision.InvalidMessage, Decide(Video() with { Id = null }));
        Assert.Equal(AutoFaceReplyDecision.InvalidMessage, Decide(Video() with { ExpiresAt = Now }));
        Assert.Equal(AutoFaceReplyDecision.MissingTimestamp, Decide(Video() with { CreatedAt = null }));
    }

    [Fact]
    public void DisplayPermissionAndCameraConditionsPreventCapture()
    {
        Assert.Equal(AutoFaceReplyDecision.DisplayAsleep, Decide(Video(), asleep: true));
        Assert.Equal(AutoFaceReplyDecision.CameraUnavailable, Decide(Video(), authorized: false));
        Assert.Equal(AutoFaceReplyDecision.CameraBusy, Decide(Video(), busy: true));
    }

    [Fact]
    public void InFlightSleepAndSlowWorkMustBeAbandoned()
    {
        Assert.Equal(AutoFaceReplyDecision.InterruptedBySleep, AutoFaceReplyPolicy.Recheck(Video(), Now, true));
        Assert.Equal(AutoFaceReplyDecision.StaleInFlight, AutoFaceReplyPolicy.Recheck(Video(), Now.AddSeconds(61), false));
        Assert.Equal(AutoFaceReplyDecision.Record, AutoFaceReplyPolicy.Recheck(Video(), Now, false));
    }

    private static AutoFaceReplyDecision Decide(VideoMessage video, IncomingArrivalSource source = IncomingArrivalSource.Live,
        bool alreadyReplied = false, bool asleep = false, bool authorized = true, bool busy = false) =>
        AutoFaceReplyPolicy.Decide(video, "me", source, Started, Now, alreadyReplied, asleep, authorized, busy);

    internal static VideoMessage Video(string id = "original") => new()
    {
        Id = id, RoomId = "group", SenderUid = "peer", ReceiverUid = "me", SenderNickname = "Peer", VideoId = "original-file",
        VideoUrl = "peer/original.mp4", DurationMs = 3000, MirrorPosition = new(.25, .8), Status = MessageStatus.Uploaded,
        CreatedAt = Now.AddSeconds(-1), ExpiresAt = Now.AddDays(1)
    };
}
