using System.Runtime.InteropServices;
using System.Text;
using Microsoft.UI.Xaml;
using Microsoft.Windows.System.Power;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

internal sealed class CaptureActivityAdapter : IDisposable
{
    private readonly CaptureActivityState state;
    private readonly IntPtr hwnd;
    private readonly SubclassProcedure procedure;
    private bool displayRegistered;
    private bool suspendRegistered;
    private bool sessionRegistered;
    private bool subclassRegistered;
    internal bool IsSessionMonitoringReady => sessionRegistered && subclassRegistered;
    internal bool IsDisplayMonitoringReady => displayRegistered && suspendRegistered;

    public CaptureActivityAdapter(Window window, CaptureActivityState state)
    {
        this.state = state;
        hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
        procedure = HandleWindowMessage;
        state.SetLocked(IsInputDesktopLocked());
        subclassRegistered = SetWindowSubclass(hwnd, procedure, 0x50494e47, 0);
        if (subclassRegistered) sessionRegistered = WTSRegisterSessionNotification(hwnd, 0);
        if (!sessionRegistered) state.SetLocked(true);
        try
        {
            PowerManager.DisplayStatusChanged += HandleDisplayChanged;
            displayRegistered = true;
            PowerManager.SystemSuspendStatusChanged += HandleSuspendChanged;
            suspendRegistered = true;
            HandleDisplayChanged(null, EventArgs.Empty);
        }
        catch (Exception error) when (error is COMException or TypeInitializationException)
        {
            state.SetDisplayAwake(false);
            System.Diagnostics.Debug.WriteLine("Ping automatic reply power monitoring is unavailable.");
        }
    }

    private void HandleDisplayChanged(object? sender, object args)
    {
        try { state.SetDisplayAwake(PowerManager.DisplayStatus is DisplayStatus.On or DisplayStatus.Dimmed); }
        catch (COMException) { state.SetDisplayAwake(false); }
    }

    private void HandleSuspendChanged(object? sender, object args)
    {
        try
        {
            if (PowerManager.SystemSuspendStatus == SystemSuspendStatus.Entering) state.SetSuspended(true);
            else if (PowerManager.SystemSuspendStatus is SystemSuspendStatus.AutoResume or SystemSuspendStatus.ManualResume)
            {
                HandleDisplayChanged(sender, args);
                state.SetSuspended(false);
            }
        }
        catch (COMException) { state.SetSuspended(true); }
    }

    private IntPtr HandleWindowMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam, nuint id, nuint data)
    {
        if (message == 0x02b1)
        {
            switch (wParam.ToInt32())
            {
                case 2: case 4: case 7: state.SetLocked(true); break;
                case 1: case 3: state.SetLocked(IsInputDesktopLocked()); break;
                case 8: state.SetLocked(false); break;
            }
        }
        return DefSubclassProc(window, message, wParam, lParam);
    }

    private static bool IsInputDesktopLocked()
    {
        var desktop = OpenInputDesktop(0, false, 1);
        if (desktop == IntPtr.Zero) return true;
        try
        {
            var name = new StringBuilder(256);
            return !GetUserObjectInformation(desktop, 2, name, name.Capacity * 2, out _)
                || !string.Equals(name.ToString(), "Default", StringComparison.OrdinalIgnoreCase);
        }
        finally { CloseDesktop(desktop); }
    }

    public void Dispose()
    {
        state.SetDisplayAwake(false);
        if (displayRegistered)
        {
            PowerManager.DisplayStatusChanged -= HandleDisplayChanged;
            displayRegistered = false;
        }
        if (suspendRegistered)
        {
            PowerManager.SystemSuspendStatusChanged -= HandleSuspendChanged;
            suspendRegistered = false;
        }
        if (sessionRegistered) { WTSUnRegisterSessionNotification(hwnd); sessionRegistered = false; }
        if (subclassRegistered) { RemoveWindowSubclass(hwnd, procedure, 0x50494e47); subclassRegistered = false; }
    }

    private delegate IntPtr SubclassProcedure(IntPtr window, uint message, IntPtr wParam, IntPtr lParam, nuint id, nuint data);
    [DllImport("comctl32.dll")] private static extern bool SetWindowSubclass(IntPtr window, SubclassProcedure proc, nuint id, nuint data);
    [DllImport("comctl32.dll")] private static extern bool RemoveWindowSubclass(IntPtr window, SubclassProcedure proc, nuint id);
    [DllImport("comctl32.dll")] private static extern IntPtr DefSubclassProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("wtsapi32.dll")] private static extern bool WTSRegisterSessionNotification(IntPtr window, uint flags);
    [DllImport("wtsapi32.dll")] private static extern bool WTSUnRegisterSessionNotification(IntPtr window);
    [DllImport("user32.dll")] private static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder info, int length, out int needed);
}
