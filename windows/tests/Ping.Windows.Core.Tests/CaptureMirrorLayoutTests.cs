using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class CaptureMirrorLayoutTests
{
    [Theory]
    [InlineData(1)]
    [InlineData(1.5)]
    [InlineData(2)]
    public void FaceIs200DipsAtEachScale(double scale)
    {
        var result = CaptureMirrorLayout.Create(CaptureMode.FaceOnly, new(-3840, 0, 3840, 2160),
            new(-3840, 0, 3840, 2080), scale, new(.5, .5));
        Assert.Equal(200, result.WidthDip);
        Assert.Equal(200, result.HeightDip);
        Assert.Equal(200 * scale, result.PixelBounds.Width);
        Assert.Equal(200 * scale, result.PixelBounds.Height);
    }

    [Theory]
    [InlineData(1920, 1080, 480, 270)]
    [InlineData(1080, 1920, 270, 480)]
    [InlineData(3840, 1080, 480, 135)]
    public void ScreenUsesActualDisplayAspectWith480DipLongSide(double width, double height, double dipWidth, double dipHeight)
    {
        var result = CaptureMirrorLayout.Create(CaptureMode.ScreenFace, new(0, 0, width, height),
            new(0, 0, width, height - 40), 1.5, new(.5, .5));
        Assert.Equal(dipWidth, result.WidthDip);
        Assert.Equal(dipHeight, result.HeightDip);
        Assert.Equal(Math.Round(dipWidth * 1.5), result.PixelBounds.Width);
    }

    [Fact]
    public void SmallWorkAreaFitsEntireMirrorAtNegativeOrigin()
    {
        var result = CaptureMirrorLayout.Create(CaptureMode.ScreenFace, new(-1920, -200, 1920, 1080),
            new(-1800, -100, 300, 200), 2, new(double.NaN, 2));
        Assert.Equal(150, result.WidthDip);
        Assert.Equal(84.375, result.HeightDip);
        Assert.Equal(-1800, result.PixelBounds.X);
        Assert.InRange(result.PixelBounds.Y, -100, -69);
        Assert.True(result.PixelBounds.Right <= -1500 && result.PixelBounds.Bottom <= 100);
    }

    [Fact]
    public void SenderPositionUsesFullDisplayInsteadOfTaskbarReducedWorkArea()
    {
        var display = new CaptureRect(-1920, -100, 1920, 1080);
        var result = CaptureMirrorLayout.Create(CaptureMode.FaceOnly, display, new(-1920, -60, 1920, 1040), 1, new(.5, .5));
        var sender = CaptureMirrorLayout.SenderPosition(result.PixelBounds, display);
        Assert.Equal(.5, sender.XRatio);
        Assert.Equal(560.0 / 1080, sender.YRatio, 8);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(double.NaN)]
    public void InvalidScaleFallsBackToOne(double scale)
    {
        var result = CaptureMirrorLayout.Create(CaptureMode.FaceOnly, new(0, 0, 1920, 1080), new(0, 0, 1920, 1040), scale, new(.5, .5));
        Assert.Equal(200, result.PixelBounds.Width);
    }

    [Fact]
    public void InvalidDisplayIsRejectedBeforeNativeSizing()
        => Assert.Throws<ArgumentException>(() => CaptureMirrorLayout.Create(CaptureMode.ScreenFace,
            new(0, 0, 0, 100), new(0, 0, 100, 100), 1, new(.5, .5)));
}
