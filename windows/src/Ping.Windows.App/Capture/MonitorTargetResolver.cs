namespace Ping.Windows.App.Capture;

public static class MonitorTargetResolver
{
    public const int DefaultMonitorIndex = -1;

    public static int ResolveIndexForWindow(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero || !OperatingSystem.IsWindows())
        {
            return DefaultMonitorIndex;
        }

#if WINDOWS
        var monitor = MonitorFromWindow(windowHandle, MonitorDefaultToNearest);
        return ResolveIndexForMonitor(monitor);
#else
        return DefaultMonitorIndex;
#endif
    }

#if WINDOWS
    private const uint MonitorDefaultToNearest = 2;

    private delegate bool MonitorEnumProc(
        IntPtr monitor,
        IntPtr hdcMonitor,
        IntPtr clipRect,
        IntPtr data);

    [System.Runtime.InteropServices.DllImport("user32.dll", ExactSpelling = true)]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [System.Runtime.InteropServices.DllImport("user32.dll", ExactSpelling = true)]
    private static extern bool EnumDisplayMonitors(
        IntPtr hdc,
        IntPtr clipRect,
        MonitorEnumProc callback,
        IntPtr data);

    private static int ResolveIndexForMonitor(IntPtr targetMonitor)
    {
        if (targetMonitor == IntPtr.Zero)
        {
            return DefaultMonitorIndex;
        }

        var currentIndex = 0;
        var resolvedIndex = DefaultMonitorIndex;
        EnumDisplayMonitors(
            IntPtr.Zero,
            IntPtr.Zero,
            (monitor, _, _, _) =>
            {
                if (monitor == targetMonitor)
                {
                    resolvedIndex = currentIndex;
                    return false;
                }

                currentIndex += 1;
                return true;
            },
            IntPtr.Zero);

        return resolvedIndex;
    }
#endif
}
