using Windows.Devices.Enumeration;

namespace Ping.Windows.App.Capture;

internal static class CaptureCameraResolver
{
    internal static async Task<string> ResolveAsync(CancellationToken token)
        => await ResolveAsync(null, token);

    internal static async Task<string> ResolveAsync(string? selectedId, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var devices = await CaptureWinRtOperation.WaitAsync(DeviceInformation.FindAllAsync(DeviceClass.VideoCapture), token);
        token.ThrowIfCancellationRequested();
        return devices.FirstOrDefault(device => device.IsEnabled && (selectedId is null || device.Id == selectedId))?.Id
            ?? throw new InvalidOperationException("사용할 카메라를 찾을 수 없습니다.");
    }
}
