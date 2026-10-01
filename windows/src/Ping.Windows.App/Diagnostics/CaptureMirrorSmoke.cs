#if PING_UI_SMOKE
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Diagnostics;

internal static class CaptureMirrorSmoke
{
    public static void Verify(Window window, bool screen, MirrorPosition senderPosition, Action<bool, string> check)
    {
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
        var scale = GetDpiForWindow(hwnd) / 96d;
        var area = DisplayArea.GetFromWindowId(window.AppWindow.Id, DisplayAreaFallback.Primary);
        var display = area.OuterBounds;
        var root = (FrameworkElement)window.Content;
        var aspect = (double)display.Width / display.Height;
        var width = screen ? aspect >= 1 ? 480 : 480 * aspect : 200;
        var height = screen ? aspect >= 1 ? 480 / aspect : 480 : 200;
        var fit = Math.Min(1, Math.Min(area.WorkArea.Width / scale / width, area.WorkArea.Height / scale / height));
        width *= fit; height *= fit;
        GetClientRect(hwnd, out var client);
        check(Math.Abs(root.ActualWidth - width) < 1 && Math.Abs(root.ActualHeight - height) < 1,
            screen ? "real screen mirror uses480DIP long side and actual display aspect" : "real face mirror uses200DIP without padding");
        check(Math.Abs(client.Right - width * scale) <= 1 && Math.Abs(client.Bottom - height * scale) <= 1,
            "real mirror client pixel dimensions match current DPI and complete XAML surface");
        var origin = new NativePoint(); ClientToScreen(hwnd, ref origin);
        check(Math.Abs(senderPosition.XRatio - (origin.X + client.Right / 2d - display.X) / display.Width) < .00001
            && Math.Abs(senderPosition.YRatio - (origin.Y + client.Bottom / 2d - display.Y) / display.Height) < .00001,
            "real mirror sends client-center ratios against full display bounds");
        var presenter = window.AppWindow.Presenter as OverlappedPresenter;
        check(presenter is { HasBorder: false, HasTitleBar: false, IsAlwaysOnTop: true, IsResizable: false },
            "real mirror is borderless always-on-top overlapped tool window");
        check(GetWindowDisplayAffinity(hwnd, out var affinity) && affinity == 0x11,
            "real mirror declares exclusion from OS capture");
        GetWindowRect(hwnd, out var outer);
        var offsetX = origin.X - outer.Left; var offsetY = origin.Y - outer.Top;
        var region = CreateRectRgn(0, 0, 0, 0);
        try
        {
            check(GetWindowRgn(hwnd, region) > 1 && !PtInRegion(region, offsetX, offsetY)
                && PtInRegion(region, offsetX + client.Right / 2, offsetY + client.Bottom / 2),
                screen ? "real screen mirror native region excludes rounded corners" : "real face mirror native region excludes square corners");
        }
        finally { DeleteObject(region); }
    }

    internal static async Task VerifyWorkAreaRefreshAsync(Window window, Action<bool, string> check)
    {
        var previous = window.AppWindow.Position;
        var area = DisplayArea.GetFromWindowId(window.AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
        try
        {
            window.AppWindow.Move(new(area.X - 12000, area.Y - 12000));
            SendMessage(hwnd, 0x001a, IntPtr.Zero, IntPtr.Zero);
            await Task.Delay(100);
            area = DisplayArea.GetFromWindowId(window.AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
            GetClientRect(hwnd, out var client);
            var origin = new NativePoint(); ClientToScreen(hwnd, ref origin);
            check(origin.X >= area.X && origin.Y >= area.Y && origin.X + client.Right <= area.X + area.Width
                && origin.Y + client.Bottom <= area.Y + area.Height,
                "owned native display-setting notification clamps complete mirror client into current work area");
        }
        finally { window.AppWindow.Move(previous); }
    }

    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref NativePoint point);
    [DllImport("user32.dll")] private static extern bool GetWindowDisplayAffinity(IntPtr hwnd, out uint affinity);
    [DllImport("user32.dll")] private static extern int GetWindowRgn(IntPtr hwnd, IntPtr region);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
    [DllImport("gdi32.dll")] private static extern bool PtInRegion(IntPtr region, int x, int y);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr region);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
#endif
