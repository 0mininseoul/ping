#if PING_UI_SMOKE
using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Windows.AppNotifications;
using Ping.Windows.App.Notifications;

namespace Ping.Windows.App.Diagnostics;

internal static class NotificationRedirectionSmoke
{
    internal static int Run(string outputDirectory, bool secondary)
    {
        Directory.CreateDirectory(outputDirectory);
        Process? child = null;
        EventHandler<AppActivationArguments>? handler = null;
        var checks = new List<string>();
        try
        {
            var decide = typeof(Program).GetMethod("DecideRedirection", BindingFlags.NonPublic | BindingFlags.Static)!;
            if (secondary)
            {
                File.WriteAllText(Path.Combine(outputDirectory, "stage.json"), "{\"Stage\":\"before actual secondary startup\"}");
                if (!(bool)decide.Invoke(null, null)!) throw new InvalidOperationException("Expected existing primary instance.");
                Write(true, null);
                return 0;
            }

            if ((bool)decide.Invoke(null, null)!) throw new InvalidOperationException("Expected fixture primary ownership.");
            var delivered = 0;
            var expected = false;
            handler = (_, arguments) =>
            {
                if (arguments.Data is AppNotificationActivatedEventArgs notification)
                {
                    var parsed = NotificationActivationArguments.From(notification);
                    expected = parsed.Action == "chat" && parsed.ChatId == "redirect-native-chat" && parsed.RoomId == "native-room";
                }
                Interlocked.Increment(ref delivered);
            };
            Program.Activated += handler;
            var start = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
            start.ArgumentList.Add("--ui-notification-redirection-output");
            start.ArgumentList.Add(Path.Combine(outputDirectory, "secondary"));
            start.ArgumentList.Add("----AppNotificationActivated:");
            child = Process.Start(start)!;
            if (child.WaitForExit(1000)) throw new InvalidOperationException($"Secondary exited before COM delivery: 0x{child.ExitCode:X8}.");
            NotificationStartupSmoke.Activate(NotificationStartupSmoke.FindFixtureActivator(), "action=chat&chat_id=redirect-native-chat&room_id=native-room");
            if (!child.WaitForExit(15000)) throw new TimeoutException("Secondary did not exit after redirecting.");
            if (child.ExitCode != 0) throw new InvalidOperationException($"Secondary failed: 0x{child.ExitCode:X8}.");
            if (!SpinWait.SpinUntil(() => Volatile.Read(ref delivered) == 1, TimeSpan.FromSeconds(10)) || !expected)
                throw new InvalidOperationException("Existing primary did not receive the expected native payload exactly once.");
            checks.Add("actual secondary process redirects its SDK COM notification payload to the existing primary exactly once");
            checks.Add("secondary exits successfully without constructing UI or opening a user account");
            Write(true, null);
            return 0;
        }
        catch (Exception error)
        {
            if (error is TargetInvocationException { InnerException: { } inner }) error = inner;
            Write(false, error.GetType().Name + $" / 0x{error.HResult:X8}: " + error.Message);
            return 1;
        }
        finally
        {
            if (handler is not null) Program.Activated -= handler;
            if (child is not null)
            {
                if (!child.HasExited) child.Kill();
                child.Dispose();
            }
        }

        void Write(bool success, string? error) => File.WriteAllText(Path.Combine(outputDirectory, "result.json"),
            JsonSerializer.Serialize(new { Success = success, Checks = checks, Error = error, Secondary = secondary,
                AppUiConstructed = false, UserAccountAccessed = false, LiteralShellClickTested = false, PackagedBrokerLaunchTested = false }));
    }
}
#endif
