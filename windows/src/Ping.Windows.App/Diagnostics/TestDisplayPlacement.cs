#if PING_UI_SMOKE
using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;

namespace Ping.Windows.App.Diagnostics;

internal static class TestDisplayPlacement
{
    private static string? Requested => Environment.GetEnvironmentVariable("PING_UI_SMOKE_DISPLAY");
    internal static void Apply(Window window)
    {
        if (string.IsNullOrWhiteSpace(Requested)) return;
        nint selected = 0;
        EnumDisplayMonitors(0, 0, (monitor, _, _, _) =>
        {
            if (!string.Equals(DeviceName(monitor), Requested, StringComparison.OrdinalIgnoreCase)) return true;
            selected = monitor;
            return false;
        }, 0);
        if (selected == 0) throw new InvalidOperationException($"Requested test display is unavailable: {Requested}");
        var work = DisplayArea.GetFromDisplayId(Win32Interop.GetDisplayIdFromMonitor(selected)).WorkArea;
        window.AppWindow.Move(new(work.X + 8, work.Y + 8));
    }

    internal static void Verify(Window window, Action<bool, string> check)
    {
        if (string.IsNullOrWhiteSpace(Requested)) return;
        var area = DisplayArea.GetFromWindowId(window.AppWindow.Id, DisplayAreaFallback.Primary);
        check(string.Equals(DeviceName(Win32Interop.GetMonitorFromDisplayId(area.DisplayId)), Requested, StringComparison.OrdinalIgnoreCase),
            $"{window.Title} is on requested test display {Requested}");
    }

    private static string DeviceName(nint monitor)
    {
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return info.DeviceName;
    }

    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct MonitorInfo
    {
        public int Size;
        public Rect Bounds, WorkArea;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
    private delegate bool MonitorCallback(nint monitor, nint deviceContext, nint clip, nint data);
    [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(nint deviceContext, nint clip, MonitorCallback callback, nint data);
}
#endif
