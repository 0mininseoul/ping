namespace Ping.Windows.Core.Capture;

public sealed record ScreenCaptureViewport
{
    public const double MinimumZoom = 1;
    public const double MaximumZoom = 4;
    public double Zoom { get; }
    public double CenterX { get; }
    public double CenterY { get; }

    public ScreenCaptureViewport(double zoom = 1, double centerX = .5, double centerY = .5)
    {
        Zoom = double.IsFinite(zoom) ? Math.Clamp(zoom, MinimumZoom, MaximumZoom) : MinimumZoom;
        var inset = .5 / Zoom;
        CenterX = ClampCenter(centerX, inset);
        CenterY = ClampCenter(centerY, inset);
    }

    public ScreenCaptureViewport AdjustZoom(double delta) => double.IsFinite(delta)
        ? new(Zoom + delta, CenterX, CenterY) : this;

    public ScreenCaptureViewport Reset() => new();

    public static double WheelAdjustment(double windowsWheelDelta) => double.IsFinite(windowsWheelDelta)
        ? windowsWheelDelta / 120 * .25 : 0;

    public ScreenCaptureViewport MoveCenterTo(double x, double y, CaptureRect display)
    {
        if (!display.IsUsable || !double.IsFinite(x) || !double.IsFinite(y)
            || x < display.X || x > display.Right || y < display.Y || y > display.Bottom) return this;
        return new(Zoom, (x - display.X) / display.Width, (y - display.Y) / display.Height);
    }

    public CaptureRect CropRect(CaptureRect extent)
    {
        if (!extent.IsUsable) return extent;
        var width = extent.Width / Zoom;
        var height = extent.Height / Zoom;
        return new(extent.X + CenterX * extent.Width - width / 2,
            extent.Y + CenterY * extent.Height - height / 2, width, height);
    }

    private static double ClampCenter(double value, double inset) =>
        Math.Clamp(double.IsFinite(value) ? value : .5, inset, 1 - inset);
}
