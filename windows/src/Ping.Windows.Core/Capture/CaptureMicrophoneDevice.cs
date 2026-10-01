namespace Ping.Windows.Core.Capture;

public sealed record CaptureMicrophoneEndpoint
{
    public string EndpointId { get; }
    public string InstanceId { get; }
    public CaptureMicrophoneEndpoint(string endpointId, string instanceId)
        => (EndpointId, InstanceId) = (CaptureMicrophoneDevice.ValidateId(endpointId), CaptureMicrophoneDevice.ValidateId(instanceId));
}

public sealed record CaptureMicrophoneInterface(string Id, string? InstanceId, bool IsEnabled);

public sealed record CaptureMicrophoneDevice
{
    public string WinRtId { get; }
    public string EndpointId { get; }
    public CaptureMicrophoneDevice(string winRtId, string endpointId)
        => (WinRtId, EndpointId) = (ValidateId(winRtId), ValidateId(endpointId));

    public static CaptureMicrophoneDevice Match(CaptureMicrophoneEndpoint endpoint, IEnumerable<CaptureMicrophoneInterface> interfaces)
    {
        ArgumentNullException.ThrowIfNull(endpoint);
        ArgumentNullException.ThrowIfNull(interfaces);
        var matches = interfaces.Where(device => device.IsEnabled
            && string.Equals(device.InstanceId, endpoint.InstanceId, StringComparison.Ordinal)).Take(2).ToArray();
        if (matches.Length != 1)
            throw new InvalidOperationException("선택한 마이크를 찾을 수 없습니다. 마이크 연결 상태를 확인해 주세요.");
        return new(matches[0].Id, endpoint.EndpointId);
    }

    internal static string ValidateId(string id)
    {
        if (string.IsNullOrWhiteSpace(id) || id.Contains('\0'))
            throw new ArgumentException("A valid opaque microphone identity is required.", nameof(id));
        return id;
    }
}
