#if PING_UI_SMOKE
using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Ping.Windows.App.Capture;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Diagnostics;

internal static class AutoReplySmoke
{
    public static async Task RunAsync(Window owner, Action<bool, string> check, Func<FrameworkElement, string, Task> render)
    {
        owner.Activate();
        await Task.Delay(100);
        var foreground = GetForegroundWindow();
        var indicator = new AutoReplyIndicatorWindow("테스트 친구");
        var closed = false;
        indicator.Closed += (_, _) => closed = true;
        try
        {
            indicator.Present();
            await Task.Delay(180);
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(indicator);
            var style = GetWindowLongPtr(hwnd, -20).ToInt64();
            var scale = GetDpiForWindow(hwnd) / 96d;
            var root = (FrameworkElement)indicator.Content;
            check(Math.Abs(root.ActualWidth - 232) < 2 && Math.Abs(root.ActualHeight - 56) < 2,
                "real auto reply indicator uses232x56DIP at current display scale");
            check((style & 0x08000080L) == 0x08000080L && (style & 0x00040000L) == 0,
                "real recording indicator is nonactivating tool window without taskbar entry");
            check(GetForegroundWindow() == foreground, "real recording indicator preserves foreground focus");
            check(indicator.SenderText == "테스트 친구님에게 보냅니다", "real indicator names only the original sender");
            var work = DisplayArea.GetFromWindowId(indicator.AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
            var position = indicator.AppWindow.Position;
            check(Math.Abs((position.Y - work.Y) / scale - 20) < 2
                && Math.Abs((work.X + work.Width - position.X - indicator.AppWindow.Size.Width) / scale - 20) < 2,
                "real recording indicator preserves20DIP work area margins");
            await render(root, "auto-reply-indicator.png");
        }
        finally { await indicator.DisposeAsync(); }
        check(closed, "real recording indicator closes and releases its timer");

        var activity = new CaptureActivityState(initiallyBlocked: true);
        using (var adapter = new CaptureActivityAdapter(owner, activity))
        {
            check(adapter.IsSessionMonitoringReady && adapter.IsDisplayMonitoringReady,
                "real display power and session lock subscriptions register successfully");
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(owner);
            // This synthetic transition must not depend on the host's display or desktop state.
            activity.SetDisplayAwake(true);
            activity.SetSuspended(false);
            activity.SetLocked(false);
            check(!activity.IsBlocked, "owned fixture starts its lock transition with capture allowed");
            var generation = activity.Generation;
            SendMessage(hwnd, 0x02b1, new IntPtr(7), IntPtr.Zero);
            check(activity.IsBlocked && activity.Generation > generation, "owned fixture lock notification blocks automatic capture");
            var lockedGeneration = activity.Generation;
            SendMessage(hwnd, 0x02b1, new IntPtr(8), IntPtr.Zero);
            check(activity.Generation == lockedGeneration, "owned fixture unlock never erases in-flight interruption");
        }
        check(activity.IsBlocked, "power adapter disposal blocks capture and removes native registrations");
    }

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
}
#endif
