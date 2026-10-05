#if PING_UI_SMOKE
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppLifecycle;
using Microsoft.Win32;
using Ping.Windows.App.Notifications;

namespace Ping.Windows.App.Diagnostics;

internal static class NotificationStartupSmoke
{
    internal static int Run(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var checks = new List<string>();
        NotificationController? controller = null;
        try
        {
            File.WriteAllText(Path.Combine(outputDirectory, "stage.json"), JsonSerializer.Serialize(new { Stage = "before actual Program primary startup", UserAccountAccessed = false }));
            var decide = typeof(Program).GetMethod("DecideRedirection", BindingFlags.NonPublic | BindingFlags.Static)!;
            if ((bool)decide.Invoke(null, null)!) throw new InvalidOperationException("Fixture must own its instance key.");
            File.WriteAllText(Path.Combine(outputDirectory, "stage.json"), JsonSerializer.Serialize(new { Stage = "primary startup returned; before SDK registration", UserAccountAccessed = false }));
            checks.Add("actual primary Program startup returns before notification registration and payload deserialization");

            var warmDelivered = 0;
            controller = new NotificationController((_, _) => throw new InvalidOperationException("Unexpected video activation"),
                (chat, room, _) =>
                {
                    if (chat != "warm-native-chat" || room != "native-room") throw new InvalidOperationException("Warm arguments changed.");
                    Interlocked.Increment(ref warmDelivered);
                    return Task.CompletedTask;
                });
            controller.Start();
            if (!controller.DiagnosticIsRegistered) throw new InvalidOperationException(controller.DiagnosticRegistrationFailure);
            checks.Add("actual SDK COM registration succeeds without constructing app UI or accessing a user account");

            var clsid = FindFixtureActivator();
            Exception? callbackError = null;
            var coldCallback = new Thread(() =>
            {
                try { Activate(clsid, "action=chat&chat_id=cold-native-chat&room_id=native-room"); }
                catch (Exception error) { callbackError = error; }
            });
            coldCallback.SetApartmentState(ApartmentState.MTA);
            coldCallback.Start();
            var initial = controller.TryGetInitialActivationArguments();
            if (!coldCallback.Join(TimeSpan.FromSeconds(15))) throw new TimeoutException("Cold callback did not finish.");
            if (callbackError is not null) throw callbackError;
            var activated = AppInstance.GetCurrent().GetActivatedEventArgs();
            File.WriteAllText(Path.Combine(outputDirectory, "activation-shape.json"), JsonSerializer.Serialize(new {
                Kind = activated.Kind.ToString(), DataType = activated.Data?.GetType().FullName,
                InitialParsed = initial is not null, InitialAction = initial?.Action,
                ExpectedChat = initial?.ChatId == "cold-native-chat", ExpectedRoom = initial?.RoomId == "native-room",
                NativeArgumentMatches = activated.Data is AppNotificationActivatedEventArgs actual && actual.Argument == "action=chat&chat_id=cold-native-chat&room_id=native-room"
            }));
            if (initial?.Action != "chat" || initial.ChatId != "cold-native-chat" || initial.RoomId != "native-room")
                throw new InvalidOperationException("Cold COM arguments were not deserialized after registration.");
            if (warmDelivered != 0) throw new InvalidOperationException("Initial activation was delivered twice.");
            checks.Add("actual cold COM payload is retained and read after registration without duplicate warm delivery");

            Activate(clsid, "action=chat&chat_id=warm-native-chat&room_id=native-room");
            if (!SpinWait.SpinUntil(() => Volatile.Read(ref warmDelivered) == 1, TimeSpan.FromSeconds(10)))
                throw new InvalidOperationException("Actual warm SDK event did not reach the controller.");
            checks.Add("subsequent actual COM callback reaches the notification controller exactly once");
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
            var registered = controller?.DiagnosticIsRegistered == true;
            controller?.Dispose();
            if (registered) AppNotificationManager.Default.Unregister();
        }

        void Write(bool success, string? error) => File.WriteAllText(Path.Combine(outputDirectory, "result.json"),
            JsonSerializer.Serialize(new { Success = success, Checks = checks, Error = error, AppUiConstructed = false,
                UserAccountAccessed = false, LiteralShellClickTested = false, PackagedBrokerLaunchTested = false }));
    }

    internal static Guid FindFixtureActivator()
    {
        var executable = Path.GetFullPath(Environment.ProcessPath!);
        using var classes = Registry.CurrentUser.OpenSubKey(@"Software\Classes\CLSID")!;
        var candidates = new List<Guid>();
        foreach (var name in classes.GetSubKeyNames())
        {
            if (!Guid.TryParse(name, out var guid)) continue;
            using var server = classes.OpenSubKey(name + @"\LocalServer32");
            if (server?.GetValue(null) is string command &&
                command.StartsWith('"' + executable + '"', StringComparison.OrdinalIgnoreCase) &&
                command.Contains("----AppNotificationActivated:", StringComparison.Ordinal)) candidates.Add(guid);
        }
        return candidates.Count == 1 ? candidates[0] : throw new InvalidOperationException("Expected one SDK activator for the fixture executable.");
    }

    internal static void Activate(Guid clsid, string arguments)
    {
        object? callback = null;
        try
        {
            callback = Activator.CreateInstance(Type.GetTypeFromCLSID(clsid, throwOnError: true)!)!;
            ((INotificationActivationCallback)callback).Activate("Ping notification startup fixture", arguments, IntPtr.Zero, 0);
        }
        finally { if (callback is not null && Marshal.IsComObject(callback)) Marshal.ReleaseComObject(callback); }
    }

    [ComImport, Guid("53E31837-6600-4A81-9395-75CFFE746F94"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface INotificationActivationCallback
    {
        void Activate([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
            [MarshalAs(UnmanagedType.LPWStr)] string invokedArgs, IntPtr data, uint count);
    }
}
#endif
