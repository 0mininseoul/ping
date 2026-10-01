using System.Runtime.InteropServices;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

public interface INativeMicrophoneCatalogApi
{
    int Enumerate(Action<string, string> found);
}

public sealed class NativeMicrophoneCatalogReader(INativeMicrophoneCatalogApi? nativeApi = null)
{
    private readonly INativeMicrophoneCatalogApi api = nativeApi ?? new NativeMicrophoneCatalogApi();
    public async Task<IReadOnlyList<CaptureMicrophoneEndpoint>> ReadAsync(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var devices = await Task.Run(() =>
        {
            var result = new List<CaptureMicrophoneEndpoint>();
            var error = api.Enumerate((endpoint, instance) => result.Add(new(endpoint, instance)));
            if (error != 0) throw NativeCaptureEngine.CreateException(error);
            return result;
        }).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        return devices;
    }
}

internal sealed class NativeMicrophoneCatalogApi : INativeMicrophoneCatalogApi
{
    [UnmanagedFunctionPointer(CallingConvention.StdCall, CharSet = CharSet.Unicode)]
    private delegate void Found([MarshalAs(UnmanagedType.LPWStr)] string endpoint,
        [MarshalAs(UnmanagedType.LPWStr)] string instance, nint context);

    public int Enumerate(Action<string, string> found)
    {
        Exception? failure = null;
        Found callback = (endpoint, instance, _) =>
        {
            try { found(endpoint, instance); }
            catch (Exception error) { failure ??= error; }
        };
        var result = PingCapture_EnumerateMicrophones(callback, 0);
        GC.KeepAlive(callback);
        if (failure is not null) throw new InvalidOperationException("마이크 목록을 읽지 못했습니다.", failure);
        return result;
    }
    [DllImport("Ping.Windows.NativeCapture.dll", CallingConvention = CallingConvention.Winapi, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_EnumerateMicrophones(Found callback, nint context);
}
