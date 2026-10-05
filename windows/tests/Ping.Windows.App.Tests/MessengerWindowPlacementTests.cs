using Ping.Windows.App.UI;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class MessengerWindowPlacementTests
{
    [Fact]
    public void ReopeningOnSavedMonitorKeepsPositionAndSize()
    {
        var work = new MessengerWorkArea(3840, 644, 1080, 1872);
        var bounds = new MessengerBounds(4000, 1000, 710, 680);
        var saved = MessengerPlacementGeometry.Capture(@"\\.\DISPLAY3", bounds, work, 1);
        Assert.Equal(bounds, MessengerPlacementGeometry.Restore(saved, work, 1));
    }

    [Fact]
    public void ChangedDpiPreservesLogicalSizeOnNegativeCoordinateMonitor()
    {
        var saved = new MessengerPlacement(@"\\.\DISPLAY3", .25, .75, 700, 650);
        Assert.Equal(new MessengerBounds(-1702, -21, 1050, 975),
            MessengerPlacementGeometry.Restore(saved, new(-1920, -100, 1920, 1080), 1.5));
    }

    [Fact]
    public void MissingMonitorAndOversizedWindowStayInsideAvailableWorkArea()
    {
        var saved = new MessengerPlacement(@"\\.\DISPLAY3", 2, -1, 10000, 10000);
        Assert.Equal(@"\\.\DISPLAY1", MessengerPlacementGeometry.SelectDevice(saved, [@"\\.\DISPLAY1"], @"\\.\DISPLAY1"));
        Assert.Equal(new MessengerBounds(0, 0, 800, 500), MessengerPlacementGeometry.Restore(saved, new(0, 0, 800, 500), 2));
    }

    [Fact]
    public void CorruptGeometryFallsBackToReadableCenteredSize()
    {
        var saved = new MessengerPlacement(@"\\.\DISPLAY3", double.NaN, double.PositiveInfinity, -1, double.NaN);
        Assert.Equal(new MessengerBounds(640, 230, 640, 620), MessengerPlacementGeometry.Restore(saved, new(0, 0, 1920, 1080), 1));
    }

    [Fact]
    public void PlacementPersistsAndCorruptFileFallsBackWithoutCrashing()
    {
        var root = Path.Combine(Path.GetTempPath(), "PingWindowPlacementTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, "MessengerWindowPlacement.json");
        try
        {
            var saved = new MessengerPlacement(@"\\.\DISPLAY3", .2, .4, 710, 680);
            Assert.True(new MessengerWindowPlacementStore(path).Save(saved));
            Assert.Equal(saved, new MessengerWindowPlacementStore(path).Load());
            File.WriteAllText(path, "{invalid");
            Assert.Null(new MessengerWindowPlacementStore(path).Load());
            var blockedPath = Path.Combine(path, "child.json");
            Assert.False(new MessengerWindowPlacementStore(blockedPath).Save(saved));
        }
        finally
        {
            var expectedParent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "PingWindowPlacementTests")) + Path.DirectorySeparatorChar;
            if (!Path.GetFullPath(root).StartsWith(expectedParent, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Unexpected test directory.");
            Directory.Delete(root, recursive: true);
        }
    }
}
