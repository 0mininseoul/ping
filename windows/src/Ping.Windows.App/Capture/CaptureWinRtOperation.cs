using Windows.Foundation;

namespace Ping.Windows.App.Capture;

internal static class CaptureWinRtOperation
{
    public static async Task WaitAsync(IAsyncAction operation, CancellationToken token)
    {
        using var registration = token.Register(() => Cancel(operation));
        // Wait for native completion before releasing camera ownership.
        await operation;
        token.ThrowIfCancellationRequested();
    }

    public static async Task<T> WaitAsync<T>(IAsyncOperation<T> operation, CancellationToken token)
    {
        using var registration = token.Register(() => Cancel(operation));
        var result = await operation;
        // Transfer returned resources to the caller even when cancellation raced completion.
        return result;
    }

    private static void Cancel(IAsyncInfo operation)
    {
        try { operation.Cancel(); }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or ObjectDisposedException) { }
    }
}
