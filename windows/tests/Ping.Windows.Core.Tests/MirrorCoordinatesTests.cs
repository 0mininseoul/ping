using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class MirrorCoordinatesTests
{
    [Theory]
    [InlineData(.25, .75)]
    [InlineData(0, 1)]
    [InlineData(1, 0)]
    public void WindowsTopOriginConvertsToMacServiceBottomOrigin(double windowsY, double serviceY)
    {
        var local = new MirrorPosition(.2, windowsY);
        var service = MirrorCoordinates.ToServicePosition(local);
        Assert.Equal(new MirrorPosition(.2, serviceY), service);
        Assert.Equal(local, MirrorCoordinates.ToWindowsPosition(service));
    }

    [Fact]
    public void InvalidCoordinatesClampBeforeConversion()
    {
        Assert.Equal(new MirrorPosition(.5, 0), MirrorCoordinates.ToServicePosition(new(double.NaN, 2)));
        Assert.Equal(new MirrorPosition(0, .5), MirrorCoordinates.ToWindowsPosition(new(-1, double.NaN)));
    }
}
