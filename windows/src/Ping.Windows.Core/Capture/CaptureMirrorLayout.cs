using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Capture;

public sealed record CaptureMirrorGeometry(double WidthDip, double HeightDip, CaptureRect PixelBounds);

public static class CaptureMirrorLayout
{
    public static CaptureMirrorGeometry Create(CaptureMode mode, CaptureRect displayPixels,
        CaptureRect workAreaPixels, double scale, MirrorPosition preferredPosition)
    {
        if (!displayPixels.IsUsable) throw new ArgumentException("Display bounds must be finite and nonempty.", nameof(displayPixels));
        if (!workAreaPixels.IsUsable || workAreaPixels.Width < 1 || workAreaPixels.Height < 1)
            throw new ArgumentException("Work area must contain at least one pixel.", nameof(workAreaPixels));
        scale = double.IsFinite(scale) && scale > 0 ? scale : 1;
        double width = 200, height = 200;
        if (mode == CaptureMode.ScreenFace)
        {
            var aspect = displayPixels.Width / displayPixels.Height;
            width = aspect >= 1 ? 480 : 480 * aspect;
            height = aspect >= 1 ? 480 / aspect : 480;
        }
        var fit = Math.Min(1, Math.Min(workAreaPixels.Width / scale / width, workAreaPixels.Height / scale / height));
        width *= fit;
        height *= fit;
        var pixelWidth = Math.Clamp(Math.Round(width * scale), 1, Math.Floor(workAreaPixels.Width));
        var pixelHeight = Math.Clamp(Math.Round(height * scale), 1, Math.Floor(workAreaPixels.Height));
        var x = workAreaPixels.X + workAreaPixels.Width * Ratio(preferredPosition.XRatio) - pixelWidth / 2;
        var y = workAreaPixels.Y + workAreaPixels.Height * Ratio(preferredPosition.YRatio) - pixelHeight / 2;
        var pixels = new CaptureRect(Math.Round(Math.Clamp(x, workAreaPixels.X, workAreaPixels.Right - pixelWidth)),
            Math.Round(Math.Clamp(y, workAreaPixels.Y, workAreaPixels.Bottom - pixelHeight)), pixelWidth, pixelHeight);
        return new(width, height, pixels);
    }

    // Top-origin ratios; the existing message boundary converts to Mac's bottom-origin Y.
    public static MirrorPosition SenderPosition(CaptureRect windowPixels, CaptureRect displayPixels)
    {
        if (!windowPixels.IsUsable || !displayPixels.IsUsable) throw new ArgumentException("Window and display must have usable bounds.");
        return new(Ratio((windowPixels.X + windowPixels.Width / 2 - displayPixels.X) / displayPixels.Width),
            Ratio((windowPixels.Y + windowPixels.Height / 2 - displayPixels.Y) / displayPixels.Height));
    }

    private static double Ratio(double value) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : .5;
}
