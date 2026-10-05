namespace Ping.Windows.App.UI;

public sealed record MessengerPlacement(string DeviceName, double XRatio, double YRatio, double WidthDips, double HeightDips);
public readonly record struct MessengerWorkArea(int X, int Y, int Width, int Height);
public readonly record struct MessengerBounds(int X, int Y, int Width, int Height);

public static class MessengerPlacementGeometry
{
    public static MessengerPlacement Capture(string device, MessengerBounds bounds, MessengerWorkArea work, double scale)
    {
        scale = ValidScale(scale);
        return new(device, PositionRatio(bounds.X - (double)work.X, work.Width - bounds.Width),
            PositionRatio(bounds.Y - (double)work.Y, work.Height - bounds.Height), bounds.Width / scale, bounds.Height / scale);
    }

    public static MessengerBounds Restore(MessengerPlacement? saved, MessengerWorkArea work, double scale)
    {
        if (work.Width <= 0 || work.Height <= 0) throw new ArgumentOutOfRangeException(nameof(work));
        scale = ValidScale(scale);
        var width = Dimension(saved?.WidthDips ?? 640, 640, 560, work.Width, scale);
        var height = Dimension(saved?.HeightDips ?? 620, 620, 540, work.Height, scale);
        return new(work.X + (int)Math.Round((work.Width - width) * Ratio(saved?.XRatio ?? .5)),
            work.Y + (int)Math.Round((work.Height - height) * Ratio(saved?.YRatio ?? .5)), width, height);
    }

    public static string SelectDevice(MessengerPlacement saved, IReadOnlyList<string> available, string fallback) =>
        available.FirstOrDefault(device => string.Equals(device, saved.DeviceName, StringComparison.OrdinalIgnoreCase)) ?? fallback;

    private static double ValidScale(double value) => double.IsFinite(value) && value > 0 ? value : 1;
    private static double Ratio(double value) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : .5;
    private static double PositionRatio(double offset, int travel) => travel > 0 ? Ratio(offset / travel) : .5;
    private static int Dimension(double value, double fallback, double minimum, int available, double scale) =>
        Math.Clamp((int)Math.Round(Math.Min(available, Math.Max(minimum * scale,
            (double.IsFinite(value) && value > 0 ? value : fallback) * scale))), 1, available);
}
