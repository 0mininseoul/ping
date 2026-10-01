#if WINDOWS
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;

namespace Ping.Windows.App.Capture;

internal sealed class CaptureDisplayObserver : IDisposable
{
    private readonly IntPtr window;
    private readonly SubclassProcedure procedure;
    private bool disposed;
    internal CaptureDisplayObserver(IntPtr window, DispatcherQueue dispatcher, Action changed)
    {
        this.window = window;
        procedure = (hwnd, message, wParam, lParam, id, data) =>
        {
            var result = DefSubclassProc(hwnd, message, wParam, lParam);
            if (!disposed && message is 0x02e0 or 0x007e or 0x001a)
                dispatcher.TryEnqueue(() => { if (!disposed) changed(); });
            return result;
        };
        if (!SetWindowSubclass(window, procedure, 0x50494e48, 0))
            throw new InvalidOperationException("거울 창의 화면 변경 알림을 등록할 수 없습니다.");
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        RemoveWindowSubclass(window, procedure, 0x50494e48);
    }
    private delegate IntPtr SubclassProcedure(IntPtr window, uint message, IntPtr wParam, IntPtr lParam, nuint id, nuint data);
    [DllImport("comctl32.dll")] private static extern bool SetWindowSubclass(IntPtr window, SubclassProcedure proc, nuint id, nuint data);
    [DllImport("comctl32.dll")] private static extern bool RemoveWindowSubclass(IntPtr window, SubclassProcedure proc, nuint id);
    [DllImport("comctl32.dll")] private static extern IntPtr DefSubclassProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
#endif
