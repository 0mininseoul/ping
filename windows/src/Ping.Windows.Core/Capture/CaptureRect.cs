namespace Ping.Windows.Core.Capture;

public readonly record struct CaptureRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
    public bool IsUsable => double.IsFinite(X) && double.IsFinite(Y)
        && double.IsFinite(Width) && double.IsFinite(Height)
        && double.IsFinite(Right) && double.IsFinite(Bottom) && Width > 0 && Height > 0;
}
