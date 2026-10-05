using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class IncomingArrivalPolicyTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-30T09:00:00Z");
    private static readonly DateTimeOffset Started = Now.AddMinutes(-5);

    [Theory]
    [InlineData(IncomingArrivalSource.Live, true)]
    [InlineData(IncomingArrivalSource.StartupCatchUp, false)]
    [InlineData(IncomingArrivalSource.ReconnectCatchUp, false)]
    public void OnlyLiveFreshArrivalAutoplays(IncomingArrivalSource source, bool autoPlay)
    {
        var decision = Decide(Video(Now.AddSeconds(-10)), source);
        Assert.True(decision.IsEligible);
        Assert.True(decision.ShouldNotify);
        Assert.Equal(autoPlay, decision.ShouldAutoPlay);
    }

    [Theory]
    [InlineData(59, true)]
    [InlineData(60, true)]
    [InlineData(61, false)]
    [InlineData(300, false)]
    public void AutoplayHonorsFreshnessAndLaunchBoundary(int ageSeconds, bool expected) =>
        Assert.Equal(expected, Decide(Video(Now.AddSeconds(-ageSeconds))).ShouldAutoPlay);

    [Fact]
    public void FreshLivePingToleratesSmallServerClockLagAtLaunch()
    {
        var launched = Now.AddSeconds(-5);
        var message = Video(Now.AddSeconds(-7));
        Assert.True(IncomingArrivalPolicy.Decide(message, "me", IncomingArrivalSource.Live, launched, Now, true).ShouldAutoPlay);
        Assert.False(IncomingArrivalPolicy.Decide(message, "me", IncomingArrivalSource.StartupCatchUp, launched, Now, true).ShouldAutoPlay);
        Assert.False(IncomingArrivalPolicy.Decide(message, "me", IncomingArrivalSource.ReconnectCatchUp, launched, Now, true).ShouldAutoPlay);
        Assert.False(IncomingArrivalPolicy.Decide(Video(launched.AddSeconds(-31)), "me", IncomingArrivalSource.Live, launched, Now, true).ShouldAutoPlay);
    }

    [Fact]
    public void DisabledPreferenceStillNotifies() =>
        Assert.Equal(new IncomingVideoDecision(true, true, false),
            IncomingArrivalPolicy.Decide(Video(Now.AddSeconds(-1)), "me", IncomingArrivalSource.Live, Started, Now, autoPlayEnabled: false));

    [Theory]
    [InlineData(IncomingArrivalSource.NotificationClick)]
    [InlineData(IncomingArrivalSource.HistoryReplay)]
    public void ExplicitReplayIgnoresAutoPlayPreferenceAndLaunchAge(IncomingArrivalSource source)
    {
        var decision = IncomingArrivalPolicy.Decide(Video(Started.AddHours(-1)), "me", source, Started, Now, autoPlayEnabled: false);
        Assert.True(decision.IsEligible);
        Assert.False(decision.ShouldNotify);
        Assert.False(decision.ShouldAutoPlay);
        Assert.True(decision.ShouldOpenPlayback);
    }

    [Fact]
    public void IncomingRequiresActualReceiverButAuthorizedHistoryMayReplayOtherRoomVideos()
    {
        var thirdPartyVideo = Video(Now.AddSeconds(-1)) with { ReceiverUid = "other" };
        Assert.False(Decide(thirdPartyVideo).IsEligible);
        Assert.True(Decide(thirdPartyVideo, IncomingArrivalSource.HistoryReplay).ShouldOpenPlayback);
    }

    [Fact]
    public void OwnDeliveryDoesNotAutoPlay() =>
        Assert.False(Decide(Video(Now.AddSeconds(-1)) with { SenderUid = "me" }).ShouldAutoPlay);

    [Fact]
    public void MissingExpiredAndFutureDatedRowsDoNotAutoPlay()
    {
        Assert.False(Decide(Video(null)).IsEligible);
        Assert.False(Decide(Video(Now.AddSeconds(-1)) with { ExpiresAt = Now }).IsEligible);
        Assert.False(Decide(Video(Now.AddMinutes(1))).IsEligible);
        Assert.False(Decide(Video(Now.AddSeconds(2))).ShouldAutoPlay);
        Assert.False(Decide(Video(Now.AddSeconds(-1)) with { Id = null }).IsEligible);
    }

    private static IncomingVideoDecision Decide(VideoMessage message, IncomingArrivalSource source = IncomingArrivalSource.Live) =>
        IncomingArrivalPolicy.Decide(message, "me", source, Started, Now, autoPlayEnabled: true);

    private static VideoMessage Video(DateTimeOffset? createdAt) => new()
    {
        Id = "video-row", RoomId = "room", SenderUid = "peer", ReceiverUid = "me", SenderNickname = "Peer", VideoId = "file",
        VideoUrl = "peer/file.mp4", DurationMs = 3000, MirrorPosition = new(0.5, 0.5), Status = MessageStatus.Uploaded,
        CreatedAt = createdAt, ExpiresAt = Now.AddHours(24)
    };
}
