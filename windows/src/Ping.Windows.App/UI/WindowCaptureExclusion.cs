#if WINDOWS
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace Ping.Windows.App.UI;

internal static class WindowCaptureExclusion
{
    internal static void Apply(Window window)
    {
        var handle = WinRT.Interop.WindowNative.GetWindowHandle(window);
        if (!SetWindowDisplayAffinity(handle, 0x11))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Ping 창을 화면 녹화에서 제외할 수 없습니다.");
    }

    internal static bool IsApplied(Window window) => GetWindowDisplayAffinity(WinRT.Interop.WindowNative.GetWindowHandle(window), out var value) && value == 0x11;
    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowDisplayAffinity(IntPtr handle, uint affinity);
    [DllImport("user32.dll")] private static extern bool GetWindowDisplayAffinity(IntPtr handle, out uint affinity);
}
#endif
