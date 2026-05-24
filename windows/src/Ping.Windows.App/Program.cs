using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace Ping.Windows.App;

public static class Program
{
    private static readonly object ActivationLock = new();
    private static readonly List<AppActivationArguments> pendingActivations = [];
    private static IntPtr redirectEventHandle = IntPtr.Zero;

    public static event EventHandler<AppActivationArguments>? Activated;

    [STAThread]
    public static int Main(string[] args)
    {
        _ = args;
        WinRT.ComWrappersSupport.InitializeComWrappers();
        if (!DecideRedirection())
        {
            Application.Start(_ =>
            {
                var context = new DispatcherQueueSynchronizationContext(
                    DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                _ = new App();
            });
        }

        return 0;
    }

    private static bool DecideRedirection()
    {
        var args = AppInstance.GetCurrent().GetActivatedEventArgs();
        var keyInstance = AppInstance.FindOrRegisterForKey("Ping.Windows.App");
        if (keyInstance.IsCurrent)
        {
            keyInstance.Activated += OnActivated;
            return false;
        }

        RedirectActivationTo(args, keyInstance);
        return true;
    }

    public static void RedirectActivationTo(AppActivationArguments args, AppInstance keyInstance)
    {
        redirectEventHandle = CreateEvent(IntPtr.Zero, true, false, null);
        Task.Run(() =>
        {
            try
            {
                keyInstance.RedirectActivationToAsync(args).AsTask().Wait();
            }
            finally
            {
                SetEvent(redirectEventHandle);
            }
        });

        _ = CoWaitForMultipleObjects(
            0,
            0xffffffff,
            1,
            [redirectEventHandle],
            out _);

        try
        {
            var process = Process.GetProcessById((int)keyInstance.ProcessId);
            if (process.MainWindowHandle != IntPtr.Zero)
            {
                SetForegroundWindow(process.MainWindowHandle);
            }
        }
        finally
        {
            if (redirectEventHandle != IntPtr.Zero)
            {
                CloseHandle(redirectEventHandle);
                redirectEventHandle = IntPtr.Zero;
            }
        }
    }

    public static IReadOnlyList<AppActivationArguments> TakePendingActivations()
    {
        lock (ActivationLock)
        {
            var activations = pendingActivations.ToArray();
            pendingActivations.Clear();
            return activations;
        }
    }

    private static void OnActivated(object? sender, AppActivationArguments args)
    {
        var handler = Activated;
        if (handler is null)
        {
            lock (ActivationLock)
            {
                pendingActivations.Add(args);
            }

            return;
        }

        handler.Invoke(sender, args);
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateEvent(
        IntPtr lpEventAttributes,
        bool bManualReset,
        bool bInitialState,
        string? lpName);

    [DllImport("kernel32.dll")]
    private static extern bool SetEvent(IntPtr hEvent);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr hObject);

    [DllImport("ole32.dll")]
    private static extern uint CoWaitForMultipleObjects(
        uint dwFlags,
        uint dwMilliseconds,
        ulong nHandles,
        IntPtr[] pHandles,
        out uint dwIndex);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
}
