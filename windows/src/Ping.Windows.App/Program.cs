using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;

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
        var diagnostic = false;
#if PING_UI_SMOKE
        if (args is ["--ui-notification-redirection-output", var redirectOutput])
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();
            return Diagnostics.NotificationRedirectionSmoke.Run(Path.GetFullPath(redirectOutput), secondary: false);
        }
        if (args is ["--ui-notification-redirection-output", var secondaryOutput, "----AppNotificationActivated:"])
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();
            return Diagnostics.NotificationRedirectionSmoke.Run(Path.GetFullPath(secondaryOutput), secondary: true);
        }
        if (args is ["--ui-notification-startup-output", var notificationOutput, "----AppNotificationActivated:"])
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();
            return Diagnostics.NotificationStartupSmoke.Run(Path.GetFullPath(notificationOutput));
        }
        if (args is ["--ui-activation-output", var activationOutput])
        {
            WinRT.ComWrappersSupport.InitializeComWrappers();
            return Diagnostics.ActivationHandoffSmoke.Run(Path.GetFullPath(activationOutput));
        }
        if (args is ["--ui-smoke-output", var output])
        {
            Diagnostics.UiSmokeRunner.OutputDirectory = Path.GetFullPath(output);
            diagnostic = true;
        }
        else if (args is ["--ui-conversation-output", var conversationOutput])
        {
            Diagnostics.UiSmokeRunner.OutputDirectory = Path.GetFullPath(conversationOutput);
            Diagnostics.UiSmokeRunner.ConversationOnly = true;
            diagnostic = true;
        }
        else if (args is ["--ui-owned-live", var liveOutput, var config, var ownedSessions, var fixtures])
        {
            Diagnostics.UiSmokeRunner.OutputDirectory = Path.GetFullPath(liveOutput);
            Diagnostics.UiSmokeRunner.OwnedLive = new(Path.GetFullPath(config), Path.GetFullPath(ownedSessions), Path.GetFullPath(fixtures));
            diagnostic = true;
        }
        else if (args is ["--ui-owned-runtime", var runtimeOutput, var runtimeConfig, var runtimeSessions, var runtimeFixtures])
        {
            Diagnostics.UiSmokeRunner.OutputDirectory = Path.GetFullPath(runtimeOutput);
            Diagnostics.UiSmokeRunner.OwnedLive = new(Path.GetFullPath(runtimeConfig), Path.GetFullPath(runtimeSessions), Path.GetFullPath(runtimeFixtures));
            Diagnostics.UiSmokeRunner.OwnedRuntime = true;
            diagnostic = true;
        }
        else return 64; // A fixture executable must never launch the real account path.
#endif
        WinRT.ComWrappersSupport.InitializeComWrappers();
        if (diagnostic || !DecideRedirection())
        {
            Application.Start(_ =>
            {
                var context = new DispatcherQueueSynchronizationContext(
                    DispatcherQueue.GetForCurrentThread());
                SynchronizationContext.SetSynchronizationContext(context);
                new App();
            });
        }

        return 0;
    }

    private static bool DecideRedirection()
    {
        var keyInstance = AppInstance.FindOrRegisterForKey("Ping.Windows.App");
        if (keyInstance.IsCurrent)
        {
            keyInstance.Activated += OnActivated;
            return false;
        }

        // COM startup arguments cannot be deserialized until this process registers.
        // The primary registers through its controller after application construction.
        var notificationStartup = Environment.GetCommandLineArgs().Contains("----AppNotificationActivated:", StringComparer.Ordinal);
        if (notificationStartup) AppNotificationManager.Default.Register();
        try
        {
            var args = AppInstance.GetCurrent().GetActivatedEventArgs();
            RedirectActivationTo(args, keyInstance);
        }
        finally
        {
            if (notificationStartup) AppNotificationManager.Default.Unregister();
        }
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
            if (args.Kind != ExtendedActivationKind.StartupTask && process.MainWindowHandle != IntPtr.Zero)
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
        EventHandler<AppActivationArguments>? handler;
        lock (ActivationLock)
        {
            // Read the handler under the same gate as the startup queue drain.
            handler = Activated;
            if (handler is null)
            {
                pendingActivations.Add(args);
                return;
            }
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
