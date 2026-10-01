using Ping.Windows.Core.Capture;
using Windows.Devices.Enumeration;
using Windows.Media.Devices;

namespace Ping.Windows.App.Capture;

internal static class CaptureMicrophoneResolver
{
    internal static async Task<CaptureMicrophoneDevice> ResolveAsync(CancellationToken token)
        => await ResolveAsync(null, token);

    internal static async Task<CaptureMicrophoneDevice> ResolveAsync(CaptureMicrophoneDevice? selected, CancellationToken token)
    {
        const string instanceProperty = "System.Devices.DeviceInstanceId";
        var endpoint = selected is null ? await new NativeMicrophoneIdentityReader().ReadAsync(token)
            : (await new NativeMicrophoneCatalogReader().ReadAsync(token)).SingleOrDefault(item => item.EndpointId == selected.EndpointId)
                ?? throw new InvalidOperationException("선택한 마이크가 연결되어 있지 않습니다. 기기 설정에서 다시 선택해 주세요.");
        var devices = await CaptureWinRtOperation.WaitAsync(DeviceInformation.FindAllAsync(
            MediaDevice.GetAudioCaptureSelector(), [instanceProperty]), token);
        token.ThrowIfCancellationRequested();
        var match = CaptureMicrophoneDevice.Match(endpoint, devices.Select(device => new CaptureMicrophoneInterface(
            device.Id, device.Properties.TryGetValue(instanceProperty, out var value) ? value as string : null, device.IsEnabled)));
        if (selected is not null && match.WinRtId != selected.WinRtId)
            throw new InvalidOperationException("선택한 마이크가 변경되었습니다. 기기 설정에서 다시 선택해 주세요.");
        return match;
    }
}
