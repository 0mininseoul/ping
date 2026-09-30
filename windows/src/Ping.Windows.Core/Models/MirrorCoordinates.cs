namespace Ping.Windows.Core.Models;

public static class MirrorCoordinates
{
    // The shared service follows macOS/AppKit's bottom origin; existing Windows placements use a top origin.
    public static MirrorPosition ToServicePosition(MirrorPosition windowsPosition) => FlipVertical(windowsPosition);
    public static MirrorPosition ToWindowsPosition(MirrorPosition servicePosition) => FlipVertical(servicePosition);

    private static MirrorPosition FlipVertical(MirrorPosition position) => new(Ratio(position.XRatio), 1 - Ratio(position.YRatio));
    private static double Ratio(double value) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : .5;
}
