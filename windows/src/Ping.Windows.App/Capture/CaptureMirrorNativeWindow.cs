#if WINDOWS
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Capture;

internal sealed record CaptureMirrorDisplay(CaptureRect Display, CaptureRect WorkArea, double Scale, int MonitorIndex);

internal sealed class CaptureMirrorNativeWindow
{
    internal IntPtr Handle { get; }
    internal AppWindow Window { get; }
    internal CaptureMirrorNativeWindow(Window window)
    {
        Handle = WinRT.Interop.WindowNative.GetWindowHandle(window);
        Window = window.AppWindow;
        var presenter = OverlappedPresenter.CreateForToolWindow();
        presenter.SetBorderAndTitleBar(false, false);
        presenter.IsAlwaysOnTop = true;
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        Window.SetPresenter(presenter);
        Ping.Windows.App.UI.WindowCaptureExclusion.Apply(window);
    }

    internal CaptureMirrorDisplay ReadDisplay()
    {
        var area = DisplayArea.GetFromWindowId(Window.Id, DisplayAreaFallback.Primary);
        return new(Rect(area.OuterBounds), Rect(area.WorkArea), GetDpiForWindow(Handle) / 96d,
            MonitorTargetResolver.ResolveIndexForWindow(Handle));
    }

    internal CaptureRect ReadClient()
    {
        Require(GetClientRect(Handle, out var client));
        var origin = new NativePoint(); Require(ClientToScreen(Handle, ref origin));
        return new(origin.X, origin.Y, client.Right - client.Left, client.Bottom - client.Top);
    }

    internal void PlaceClient(CaptureRect bounds)
    {
        Window.ResizeClient(new(checked((int)bounds.Width), checked((int)bounds.Height)));
        MoveClient(bounds.X, bounds.Y);
    }

    internal void MoveClient(double x, double y)
    {
        Require(GetWindowRect(Handle, out var outer));
        var origin = new NativePoint(); Require(ClientToScreen(Handle, ref origin));
        Window.Move(new(checked((int)Math.Round(x)) - (origin.X - outer.Left), checked((int)Math.Round(y)) - (origin.Y - outer.Top)));
    }

    internal void ApplyRegion(CaptureMode mode, double scale)
    {
        Require(GetWindowRect(Handle, out var outer));
        var client = ReadClient();
        var x = checked((int)client.X) - outer.Left; var y = checked((int)client.Y) - outer.Top;
        var right = x + checked((int)client.Width) + 1; var bottom = y + checked((int)client.Height) + 1;
        var region = mode == CaptureMode.FaceOnly ? CreateEllipticRgn(x, y, right, bottom)
            : CreateRoundRectRgn(x, y, right, bottom, (int)Math.Round(32 * scale), (int)Math.Round(32 * scale));
        if (region == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        if (SetWindowRgn(Handle, region, true) == 0)
        {
            var error = Marshal.GetLastWin32Error(); DeleteObject(region); throw new Win32Exception(error);
        }
    }

    internal static (double X, double Y) Cursor()
    {
        Require(GetCursorPos(out var point)); return (point.X, point.Y);
    }
    private static CaptureRect Rect(global::Windows.Graphics.RectInt32 rect) => new(rect.X, rect.Y, rect.Width, rect.Height);
    private static void Require(bool success) { if (!success) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool GetClientRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool ClientToScreen(IntPtr hwnd, ref NativePoint point);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowRgn(IntPtr hwnd, IntPtr region, bool redraw);
    [DllImport("gdi32.dll", SetLastError = true)] private static extern IntPtr CreateEllipticRgn(int left, int top, int right, int bottom);
    [DllImport("gdi32.dll", SetLastError = true)] private static extern IntPtr CreateRoundRectRgn(int left, int top, int right, int bottom, int width, int height);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr region);
}
#endif
