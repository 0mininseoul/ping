using Ping.Windows.Core.Capture;
using Windows.Devices.Enumeration;
using Windows.Media.Devices;

namespace Ping.Windows.App.Capture;

internal static class CaptureMicrophoneResolver
{
    internal static async Task<CaptureMicrophoneDevice> ResolveAsync(CancellationToken token)
    {
        const string instanceProperty = "System.Devices.DeviceInstanceId";
        var endpoint = await new NativeMicrophoneIdentityReader().ReadAsync(token);
        var devices = await CaptureWinRtOperation.WaitAsync(DeviceInformation.FindAllAsync(
            MediaDevice.GetAudioCaptureSelector(), [instanceProperty]), token);
        token.ThrowIfCancellationRequested();
        return CaptureMicrophoneDevice.Match(endpoint, devices.Select(device => new CaptureMicrophoneInterface(
            device.Id, device.Properties.TryGetValue(instanceProperty, out var value) ? value as string : null, device.IsEnabled)));
    }
}
