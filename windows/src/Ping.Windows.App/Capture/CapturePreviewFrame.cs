namespace Ping.Windows.App.Capture;

public sealed class CapturePreviewFrame
{
    public int Width { get; }
    public int Height { get; }
    public ReadOnlyMemory<byte> Pixels { get; }

    // The producer transfers its owned top-down BGRA copy to this frame.
    public CapturePreviewFrame(int width, int height, byte[] pixels)
    {
        ArgumentNullException.ThrowIfNull(pixels);
        if (width < 2 || height < 2 || width > 1920 || height > 1920 || pixels.Length != checked(width * height * 4))
            throw new ArgumentException("Preview frame dimensions do not match its pixels.");
        Width = width; Height = height; Pixels = pixels;
    }
}
