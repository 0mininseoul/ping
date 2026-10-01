#if WINDOWS
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;

namespace Ping.Windows.App.UI;

internal static class SettingsWindowGeometry
{
    internal static void Fit(Window window)
    {
        var appWindow = window.AppWindow;
        var work = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var scale = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(window)) / 96d;
        var width = Math.Max(1, Math.Min((int)Math.Round(760 * scale), work.Width - 48));
        var height = Math.Max(1, Math.Min((int)Math.Round(620 * scale), work.Height - 100));
        appWindow.ResizeClient(new(width, height));
        appWindow.Move(new(work.X + Math.Max(0, (work.Width - appWindow.Size.Width) / 2),
            work.Y + Math.Max(0, (work.Height - appWindow.Size.Height) / 2)));
    }
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(nint window);
}
#endif
