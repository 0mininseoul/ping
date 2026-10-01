using System.Runtime.InteropServices;
using System.Text;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

public interface INativeMicrophoneIdentityApi
{
    int Read(StringBuilder endpoint, int endpointCapacity, StringBuilder instance, int instanceCapacity);
}

public sealed class NativeMicrophoneIdentityReader(INativeMicrophoneIdentityApi? nativeApi = null)
{
    private readonly INativeMicrophoneIdentityApi api = nativeApi ?? new NativeMicrophoneIdentityApi();
    public async Task<CaptureMicrophoneEndpoint> ReadAsync(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var identity = await Task.Run(() =>
        {
            const int capacity = 32768;
            var endpoint = new StringBuilder(capacity);
            var instance = new StringBuilder(capacity);
            var result = api.Read(endpoint, capacity, instance, capacity);
            if (result != 0) throw NativeCaptureEngine.CreateException(result);
            return new CaptureMicrophoneEndpoint(endpoint.ToString(), instance.ToString());
        }).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        return identity;
    }
}

internal sealed class NativeMicrophoneIdentityApi : INativeMicrophoneIdentityApi
{
    public int Read(StringBuilder endpoint, int endpointCapacity, StringBuilder instance, int instanceCapacity)
        => PingCapture_GetDefaultMicrophoneIdentity(endpoint, endpointCapacity, instance, instanceCapacity);
    [DllImport("Ping.Windows.NativeCapture.dll", CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_GetDefaultMicrophoneIdentity([Out] StringBuilder endpoint, int endpointCapacity,
        [Out] StringBuilder instance, int instanceCapacity);
}
