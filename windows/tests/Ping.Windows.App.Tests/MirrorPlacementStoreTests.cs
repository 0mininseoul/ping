using Ping.Windows.App.Capture;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class MirrorPlacementStoreTests
{
    [Fact]
    public void SaveThenLoad_KeepsPositionsPerCaptureMode()
    {
        var store = new MirrorPlacementStore(TempFilePath());

        store.Save(CaptureMode.FaceOnly, new MirrorPosition(0.2, 0.3));
        store.Save(CaptureMode.ScreenFace, new MirrorPosition(0.7, 0.8));

        Assert.Equal(0.2, store.Load(CaptureMode.FaceOnly).XRatio, precision: 6);
        Assert.Equal(0.3, store.Load(CaptureMode.FaceOnly).YRatio, precision: 6);
        Assert.Equal(0.7, store.Load(CaptureMode.ScreenFace).XRatio, precision: 6);
        Assert.Equal(0.8, store.Load(CaptureMode.ScreenFace).YRatio, precision: 6);
    }

    [Fact]
    public void Load_WhenFileIsMissingOrInvalid_ReturnsCenter()
    {
        var path = TempFilePath();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "{not-json");

        var position = new MirrorPlacementStore(path).Load(CaptureMode.ScreenFace);

        Assert.Equal(0.5, position.XRatio, precision: 6);
        Assert.Equal(0.5, position.YRatio, precision: 6);
    }

    [Fact]
    public void Save_ClampsRatiosBeforePersisting()
    {
        var store = new MirrorPlacementStore(TempFilePath());

        store.Save(CaptureMode.ScreenFace, new MirrorPosition(-1, 2));
        var position = store.Load(CaptureMode.ScreenFace);

        Assert.Equal(0, position.XRatio, precision: 6);
        Assert.Equal(1, position.YRatio, precision: 6);
    }

    private static string TempFilePath() =>
        Path.Combine(
            Path.GetTempPath(),
            "PingMirrorPlacementStoreTests",
            Guid.NewGuid().ToString("N"),
            "MirrorPlacement.json");
}
