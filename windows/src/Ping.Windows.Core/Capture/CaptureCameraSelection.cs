namespace Ping.Windows.Core.Capture;

public sealed class CaptureCameraSelection : CaptureDeviceSelection<string>
{
    internal CaptureCameraSelection(CancellationToken lifetime) : base(lifetime, id =>
    {
        if (string.IsNullOrWhiteSpace(id) || id.Contains('\0'))
            throw new InvalidOperationException("사용할 카메라를 찾을 수 없습니다.");
    }) { }
}
