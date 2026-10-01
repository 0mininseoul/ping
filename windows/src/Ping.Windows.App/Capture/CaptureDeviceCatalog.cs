using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

public sealed record CameraChoice(string? Id, string Label);
public sealed record MicrophoneChoice(CaptureMicrophoneDevice? Device, string Label);
public sealed record CaptureDeviceCatalog(IReadOnlyList<CameraChoice> Cameras, IReadOnlyList<MicrophoneChoice> Microphones, string? Warning = null);

#if WINDOWS
internal static class WindowsCaptureDeviceCatalog
{
    internal static async Task<CaptureDeviceCatalog> ReadAsync(CancellationToken token)
    {
        var cameras = await CaptureWinRtOperation.WaitAsync(global::Windows.Devices.Enumeration.DeviceInformation.FindAllAsync(
            global::Windows.Devices.Enumeration.DeviceClass.VideoCapture), token);
        var microphoneChoices = new List<MicrophoneChoice>();
        string? warning = null;
        try
        {
            const string instanceProperty = "System.Devices.DeviceInstanceId";
            var endpoints = await new NativeMicrophoneCatalogReader().ReadAsync(token);
            var interfaces = await CaptureWinRtOperation.WaitAsync(global::Windows.Devices.Enumeration.DeviceInformation.FindAllAsync(
                global::Windows.Media.Devices.MediaDevice.GetAudioCaptureSelector(), [instanceProperty]), token);
            var identities = interfaces.Select(device => new CaptureMicrophoneInterface(device.Id,
                device.Properties.TryGetValue(instanceProperty, out var value) ? value as string : null, device.IsEnabled)).ToArray();
            foreach (var endpoint in endpoints)
            {
                CaptureMicrophoneDevice match;
                try { match = CaptureMicrophoneDevice.Match(endpoint, identities); }
                catch (InvalidOperationException) { continue; }
                microphoneChoices.Add(new(match, interfaces.Single(device => device.Id == match.WinRtId).Name));
            }
        }
        catch (Exception error) when (error is InvalidOperationException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException)
        { warning = "마이크 목록을 읽지 못했어요. 연결과 Windows 마이크 권한을 확인해 주세요."; }
        return new(cameras.Where(device => device.IsEnabled).Select(device => new CameraChoice(device.Id, device.Name)).ToArray(),
            microphoneChoices, warning);
    }
}
#endif
