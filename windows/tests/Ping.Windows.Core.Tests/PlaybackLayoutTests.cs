using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class PlaybackLayoutTests
{
    [Theory]
    [InlineData(1)]
    [InlineData(1.5)]
    [InlineData(2)]
    public void FaceIs200DipsAtEveryScaleAndClampedToNegativeOriginDisplay(double scale)
    {
        var work = new PlaybackRect(-1920 / scale, 0, 1920 / scale, 1080 / scale);
        var result = PlaybackLayout.Single(CaptureMode.FaceOnly, null, new(double.NaN, 2), work, false);
        Assert.Equal(200, result.Width);
        Assert.Equal(200, result.Height);
        Assert.True(result.X >= work.X && result.Right <= work.Right);
        Assert.True(result.Y >= work.Y && result.Bottom <= work.Bottom);
    }

    [Theory]
    [InlineData(16.0 / 9)]
    [InlineData(.5)]
    [InlineData(3)]
    public void HistoryScreenFits600DipTargetAnd32DipMargin(double aspect)
    {
        var work = new PlaybackRect(0, 0, 800, 600);
        var result = PlaybackLayout.Single(CaptureMode.ScreenFace, aspect, new(0, 0), work, true);
        Assert.InRange(result.Width, 1, 600);
        Assert.Equal(aspect, result.Width / result.Height, 5);
        Assert.True(result.X >= 32 && result.Y >= 32 && result.Right <= 768 && result.Bottom <= 568);
    }

    [Fact]
    public void LivePortraitUses480DipLongSideAndHistoryCentersOnParent()
    {
        var work = new PlaybackRect(0, 0, 1920, 1080);
        var live = PlaybackLayout.Single(CaptureMode.ScreenFace, .5, new(.5, .5), work, false);
        Assert.Equal(240, live.Width);
        Assert.Equal(480, live.Height);
        var history = PlaybackLayout.Single(CaptureMode.ScreenFace, 2, new(0, 0), work, true, new(600, 200, 600, 600));
        Assert.Equal(900, history.X + history.Width / 2);
        Assert.Equal(500, history.Y + history.Height / 2);
    }

    [Fact]
    public void MacUpperScreenWirePositionAppearsAtSameWindowsVisualPosition()
    {
        var result = PlaybackLayout.Single(CaptureMode.FaceOnly, 1, new(.25, .8), new(0, 0, 1920, 1080), false);
        Assert.Equal(480, result.X + result.Width / 2, 5);
        Assert.Equal(216, result.Y + result.Height / 2, 5);
    }

    [Theory]
    [InlineData(7, 1440, 900)]
    [InlineData(7, 420, 400)]
    [InlineData(2, 800, 600)]
    public void ReplyGroupNeverOverlapsAndFitsAvailableDisplay(int count, double width, double height)
    {
        var work = new PlaybackRect(-width, 20, width, height);
        var group = PlaybackLayout.Group(Enumerable.Repeat(new PlaybackRect(0, 0, 200, 200), count).ToArray(), new(.99, .01), work);
        Assert.Equal(count, group.Count);
        foreach (var item in group)
        {
            Assert.True(item.X >= work.X && item.Y >= work.Y && item.Right <= work.Right + .001 && item.Bottom <= work.Bottom + .001);
            Assert.DoesNotContain(group, other => other != item && item.X < other.Right && item.Right > other.X && item.Y < other.Bottom && item.Bottom > other.Y);
        }
    }
}
