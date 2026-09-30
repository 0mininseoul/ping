using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class ScreenCaptureViewportTests
{
    [Fact]
    public void DefaultIncludesTheWholeSource()
    {
        var viewport = new ScreenCaptureViewport();
        Assert.Equal(new CaptureRect(0, 0, 3840, 2160), viewport.CropRect(new(0, 0, 3840, 2160)));
        Assert.Equal(1, viewport.Zoom);
    }

    [Theory]
    [InlineData(-10, 1)]
    [InlineData(9, 4)]
    [InlineData(double.NaN, 1)]
    [InlineData(double.PositiveInfinity, 1)]
    public void ZoomIsBoundedAndNonfiniteValuesAreSafe(double zoom, double expected)
        => Assert.Equal(expected, new ScreenCaptureViewport(zoom).Zoom);

    [Fact]
    public void EdgeCentersKeepCropInsideSourceAndPreserveAspect()
    {
        var viewport = new ScreenCaptureViewport(4, -1, 2);
        Assert.Equal(new CaptureRect(0, 810, 480, 270), viewport.CropRect(new(0, 0, 1920, 1080)));
        Assert.Equal(.125, viewport.CenterX);
        Assert.Equal(.875, viewport.CenterY);
    }

    [Fact]
    public void NonfiniteCenterFallsBackToSourceCenter()
        => Assert.Equal(new CaptureRect(480, 270, 960, 540),
            new ScreenCaptureViewport(2, double.NaN, double.PositiveInfinity).CropRect(new(0, 0, 1920, 1080)));

    [Fact]
    public void PointerUsesTheWholeDisplayWithNegativeOrigin()
    {
        var viewport = new ScreenCaptureViewport(2).MoveCenterTo(-1800, -100, new(-1920, -200, 1920, 1080));
        Assert.Equal(.25, viewport.CenterX);
        Assert.Equal(.25, viewport.CenterY);
        Assert.Equal(new CaptureRect(-1920, -200, 960, 540), viewport.CropRect(new(-1920, -200, 1920, 1080)));
    }

    [Theory]
    [InlineData(-1921, 0)]
    [InlineData(1, 0)]
    [InlineData(-100, -201)]
    [InlineData(-100, 881)]
    [InlineData(double.NaN, 0)]
    public void PointerOutsideCapturedDisplayDoesNotMoveCenter(double x, double y)
    {
        var viewport = new ScreenCaptureViewport(3);
        Assert.Same(viewport, viewport.MoveCenterTo(x, y, new(-1920, -200, 1920, 1080)));
    }

    [Fact]
    public void ZoomOutRecentersWithoutMutatingRecordingSnapshot()
    {
        var snapshot = new ScreenCaptureViewport(4, .125, .875);
        var changed = snapshot.AdjustZoom(-3);
        Assert.Equal(new ScreenCaptureViewport(), changed);
        Assert.Equal(4, snapshot.Zoom);
        Assert.Equal(.125, snapshot.CenterX);
        Assert.Equal(new ScreenCaptureViewport(), snapshot.Reset());
    }

    [Theory]
    [InlineData(120, .25)]
    [InlineData(-240, -.5)]
    [InlineData(15, .03125)]
    [InlineData(0, 0)]
    [InlineData(double.NaN, 0)]
    public void WindowsWheelPreservesFractionalDelta(double delta, double expected)
        => Assert.Equal(expected, ScreenCaptureViewport.WheelAdjustment(delta));

    [Fact]
    public void InvalidExtentIsReturnedWithoutProducingAnotherInvalidCrop()
    {
        var extent = new CaptureRect(0, 0, 0, 20);
        Assert.Equal(extent, new ScreenCaptureViewport(2).CropRect(extent));
        var viewport = new ScreenCaptureViewport(2);
        Assert.Same(viewport, viewport.MoveCenterTo(0, 0, extent));
    }
}
