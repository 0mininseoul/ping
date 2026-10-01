using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class CaptureDevicePreferencesTests
{
    [Fact]
    public void SelectionChangesApplyToNextLeaseOnly()
    {
        var selected = new CaptureDevicePreferences("camera-a", new("winrt-a", "endpoint-a"));
        var owner = new CameraOwnership(() => selected);
        using (var active = owner.TryAcquire(CameraPurpose.Manual)!)
        {
            selected = new("camera-b", new("winrt-b", "endpoint-b"));
            Assert.Equal("camera-a", active.Devices.CameraId);
            Assert.Equal("endpoint-a", active.Devices.Microphone?.EndpointId);
        }
        using var next = owner.TryAcquire(CameraPurpose.AutomaticReply)!;
        Assert.Equal("camera-b", next.Devices.CameraId);
        Assert.Equal("winrt-b", next.Devices.Microphone?.WinRtId);
    }
}
