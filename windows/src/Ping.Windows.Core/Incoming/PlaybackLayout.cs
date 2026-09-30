using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Incoming;

public readonly record struct PlaybackRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

public static class PlaybackLayout
{
    public static PlaybackRect Single(CaptureMode mode, double? aspectRatio, MirrorPosition position, PlaybackRect workArea,
        bool historyReplay, PlaybackRect? parent = null)
    {
        var aspect = aspectRatio is { } value && double.IsFinite(value) && value > 0 ? Math.Clamp(value, .5, 3) : 16.0 / 9;
        var width = mode == CaptureMode.FaceOnly ? 200 : historyReplay ? 600 : aspect >= 1 ? 480 : 480 * aspect;
        var height = mode == CaptureMode.FaceOnly ? 200 : width / aspect;
        var margin = mode == CaptureMode.ScreenFace && historyReplay ? 32d : 0;
        var safe = Inset(workArea, margin);
        var scale = Math.Min(1, Math.Min(safe.Width / width, safe.Height / height));
        width *= scale;
        height *= scale;
        var centerX = historyReplay && mode == CaptureMode.ScreenFace && parent is { } owner
            ? owner.X + owner.Width / 2 : workArea.X + workArea.Width * Ratio(position.XRatio);
        var centerY = historyReplay && mode == CaptureMode.ScreenFace && parent is { } ownerY
            ? ownerY.Y + ownerY.Height / 2 : workArea.Y + workArea.Height * MirrorCoordinates.ToWindowsPosition(position).YRatio;
        return Clamp(new(centerX - width / 2, centerY - height / 2, width, height), safe);
    }

    public static IReadOnlyList<PlaybackRect> Group(IReadOnlyList<PlaybackRect> sizes, MirrorPosition center, PlaybackRect workArea)
    {
        if (sizes.Count == 0) return [];
        const double spacing = 12;
        var cellWidth = sizes.Max(size => size.Width);
        var cellHeight = sizes.Max(size => size.Height);
        var columns = Math.Max(1, Math.Min(Math.Min(3, sizes.Count), (int)Math.Floor((workArea.Width + spacing) / (cellWidth + spacing))));
        var rows = (int)Math.Ceiling((double)sizes.Count / columns);
        var blockWidth = columns * cellWidth + (columns - 1) * spacing;
        var blockHeight = rows * cellHeight + (rows - 1) * spacing;
        var scale = Math.Min(1, Math.Min(workArea.Width / blockWidth, workArea.Height / blockHeight));
        var block = Clamp(new(workArea.X + workArea.Width * Ratio(center.XRatio) - blockWidth * scale / 2,
            workArea.Y + workArea.Height * MirrorCoordinates.ToWindowsPosition(center).YRatio - blockHeight * scale / 2, blockWidth * scale, blockHeight * scale), workArea);
        return sizes.Select((size, index) =>
        {
            var row = index / columns;
            var column = index % columns;
            var inRow = Math.Min(columns, sizes.Count - row * columns);
            var rowWidth = (inRow * cellWidth + (inRow - 1) * spacing) * scale;
            return new PlaybackRect(block.X + (block.Width - rowWidth) / 2 + (column * (cellWidth + spacing) + (cellWidth - size.Width) / 2) * scale,
                block.Y + (row * (cellHeight + spacing) + (cellHeight - size.Height) / 2) * scale, size.Width * scale, size.Height * scale);
        }).ToArray();
    }

    private static PlaybackRect Inset(PlaybackRect area, double margin)
    {
        var horizontal = Math.Min(margin, Math.Max(0, (area.Width - 1) / 2));
        var vertical = Math.Min(margin, Math.Max(0, (area.Height - 1) / 2));
        return new(area.X + horizontal, area.Y + vertical, Math.Max(1, area.Width - 2 * horizontal), Math.Max(1, area.Height - 2 * vertical));
    }

    private static PlaybackRect Clamp(PlaybackRect rect, PlaybackRect area) => new(
        Math.Clamp(rect.X, area.X, Math.Max(area.X, area.Right - rect.Width)),
        Math.Clamp(rect.Y, area.Y, Math.Max(area.Y, area.Bottom - rect.Height)), rect.Width, rect.Height);

    private static double Ratio(double value) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : .5;
}
