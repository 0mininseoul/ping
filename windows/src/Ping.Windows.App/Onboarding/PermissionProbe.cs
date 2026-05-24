using System.Runtime.InteropServices;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Setup;

namespace Ping.Windows.App.Onboarding;

public interface INativeScreenCaptureSelfTest
{
    Task<OnboardingProbeState> CapturePrimaryMonitorFrameAsync(CancellationToken cancellationToken = default);
}

public interface IHotkeyRegistrationProbe
{
    bool TryRegister(int id, uint modifiers, uint virtualKey);

    void Unregister(int id);
}

public interface IElevationProbe
{
    bool IsElevated { get; }
}

public sealed class PermissionProbe
{
    private readonly string supabaseConfigPath;
    private readonly INativeScreenCaptureSelfTest screenCaptureSelfTest;
    private readonly IHotkeyRegistrationProbe? hotkeyRegistrationProbe;
    private readonly IStartupTaskController startupTaskController;
    private readonly IElevationProbe elevationProbe;
    private readonly Func<IReadOnlyDictionary<HotkeyCommand, HotkeyBinding>> hotkeyBindingsProvider;
    private readonly Func<IReadOnlyList<HotkeyRegistrationResult>>? activeHotkeyRegistrationsProvider;

    public PermissionProbe(
        string? supabaseConfigPath = null,
        INativeScreenCaptureSelfTest? screenCaptureSelfTest = null,
        IHotkeyRegistrationProbe? hotkeyRegistrationProbe = null,
        IStartupTaskController? startupTaskController = null,
        IElevationProbe? elevationProbe = null,
        Func<IReadOnlyDictionary<HotkeyCommand, HotkeyBinding>>? hotkeyBindingsProvider = null,
        Func<IReadOnlyList<HotkeyRegistrationResult>>? activeHotkeyRegistrationsProvider = null)
    {
        this.supabaseConfigPath = supabaseConfigPath ?? DefaultSupabaseConfigPath();
        this.screenCaptureSelfTest = screenCaptureSelfTest ?? new NativeScreenCaptureSelfTest();
        this.hotkeyRegistrationProbe = hotkeyRegistrationProbe;
        this.startupTaskController = startupTaskController ?? new StartupTaskController();
        this.elevationProbe = elevationProbe ?? new WindowsElevationProbe();
        this.hotkeyBindingsProvider = hotkeyBindingsProvider ?? HotkeyBinding.Defaults;
        this.activeHotkeyRegistrationsProvider = activeHotkeyRegistrationsProvider;
    }

    public async Task<OnboardingEnvironmentState> ProbeAsync(CancellationToken cancellationToken = default) =>
        new(
            WindowsVersionProbe.CurrentStatus(),
            IsSupabaseConfigured(),
            await CheckCameraAsync(cancellationToken).ConfigureAwait(false),
            await CheckMicrophoneAsync(cancellationToken).ConfigureAwait(false),
            await CheckScreenCaptureAsync(cancellationToken).ConfigureAwait(false),
            await CheckNotificationsAsync(cancellationToken).ConfigureAwait(false),
            CheckDefaultHotkeys(),
            await CheckStartupAsync(cancellationToken).ConfigureAwait(false));

    public bool IsSupabaseConfigured() =>
        File.Exists(supabaseConfigPath);

    public async Task<OnboardingProbeState> CheckCameraAsync(CancellationToken cancellationToken = default)
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        var capability = Windows.Security.Authorization.AppCapabilityAccess.AppCapability.Create("Webcam");
        var access = capability.CheckAccess();
        if (access != Windows.Security.Authorization.AppCapabilityAccess.AppCapabilityAccessStatus.Allowed)
        {
            return OnboardingProbeState.Blocked(
                $"Camera privacy access is {access}.",
                SettingsLauncher.WebcamPrivacyUri);
        }

        try
        {
            using var capture = new Windows.Media.Capture.MediaCapture();
            await capture.InitializeAsync(new Windows.Media.Capture.MediaCaptureInitializationSettings
            {
                StreamingCaptureMode = Windows.Media.Capture.StreamingCaptureMode.Video
            });
            return OnboardingProbeState.Available("Camera is ready.");
        }
        catch (UnauthorizedAccessException ex)
        {
            return OnboardingProbeState.Blocked(ex.Message, SettingsLauncher.WebcamPrivacyUri);
        }
        catch (COMException ex) when ((uint)ex.HResult == 0x80070005)
        {
            return OnboardingProbeState.Blocked(ex.Message, SettingsLauncher.WebcamPrivacyUri);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return OnboardingProbeState.Blocked($"Camera initialization failed: {ex.Message}", SettingsLauncher.WebcamPrivacyUri);
        }
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return OnboardingProbeState.Unchecked("Camera permission check requires Windows runtime APIs.");
#endif
    }

    public async Task<OnboardingProbeState> CheckMicrophoneAsync(CancellationToken cancellationToken = default)
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        var capability = Windows.Security.Authorization.AppCapabilityAccess.AppCapability.Create("Microphone");
        var access = capability.CheckAccess();
        if (access != Windows.Security.Authorization.AppCapabilityAccess.AppCapabilityAccessStatus.Allowed)
        {
            return OnboardingProbeState.Blocked(
                $"Microphone privacy access is {access}.",
                SettingsLauncher.MicrophonePrivacyUri);
        }

        try
        {
            using var capture = new Windows.Media.Capture.MediaCapture();
            await capture.InitializeAsync(new Windows.Media.Capture.MediaCaptureInitializationSettings
            {
                StreamingCaptureMode = Windows.Media.Capture.StreamingCaptureMode.Audio
            });
            return OnboardingProbeState.Available("Microphone is ready.");
        }
        catch (UnauthorizedAccessException ex)
        {
            return OnboardingProbeState.Blocked(ex.Message, SettingsLauncher.MicrophonePrivacyUri);
        }
        catch (COMException ex) when ((uint)ex.HResult == 0x80070005)
        {
            return OnboardingProbeState.Blocked(ex.Message, SettingsLauncher.MicrophonePrivacyUri);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return OnboardingProbeState.Blocked($"Microphone initialization failed: {ex.Message}", SettingsLauncher.MicrophonePrivacyUri);
        }
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return OnboardingProbeState.Unchecked("Microphone permission check requires Windows runtime APIs.");
#endif
    }

    public async Task<OnboardingProbeState> CheckScreenCaptureAsync(CancellationToken cancellationToken = default)
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        if (!Windows.Graphics.Capture.GraphicsCaptureSession.IsSupported())
        {
            return OnboardingProbeState.Unsupported("Graphics Capture is not supported on this device.");
        }

        var selfTest = await screenCaptureSelfTest.CapturePrimaryMonitorFrameAsync(cancellationToken).ConfigureAwait(false);
        return selfTest.Status switch
        {
            OnboardingProbeStatus.Available => selfTest,
            OnboardingProbeStatus.Blocked => selfTest,
            OnboardingProbeStatus.Unsupported => selfTest,
            _ => OnboardingProbeState.Blocked("Screen capture support exists, but the native one-frame self-test did not complete.")
        };
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return OnboardingProbeState.Unchecked("Screen capture check requires Windows Graphics Capture runtime APIs.");
#endif
    }

    public Task<OnboardingProbeState> CheckNotificationsAsync(CancellationToken cancellationToken = default)
    {
        _ = cancellationToken;
        if (elevationProbe.IsElevated)
        {
            return Task.FromResult(OnboardingProbeState.Blocked(
                "Windows app notifications are unavailable while Ping runs as administrator.",
                actionKind: OnboardingActionKind.Relaunch,
                actionLabel: "Restart normally"));
        }

#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        try
        {
            Microsoft.Windows.AppNotifications.AppNotificationManager.Default.Register();
            var setting = Microsoft.Windows.AppNotifications.AppNotificationManager.Default.Setting;
            if (setting != Microsoft.Windows.AppNotifications.AppNotificationSetting.Enabled)
            {
                return Task.FromResult(OnboardingProbeState.Blocked(
                    $"Notifications are {setting}.",
                    SettingsLauncher.NotificationsPrivacyUri));
            }

            var notification = new Microsoft.Windows.AppNotifications.AppNotification(
                "<toast><visual><binding template=\"ToastGeneric\"><text>Ping notification test</text></binding></visual></toast>");
            Microsoft.Windows.AppNotifications.AppNotificationManager.Default.Show(notification);
            return Task.FromResult(OnboardingProbeState.Available("Notifications are ready."));
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return Task.FromResult(OnboardingProbeState.Blocked(
                $"Notification registration failed: {ex.Message}",
                SettingsLauncher.NotificationsPrivacyUri));
        }
#else
        return Task.FromResult(OnboardingProbeState.Unchecked("Notification check requires Windows App SDK runtime APIs."));
#endif
    }

    public OnboardingProbeState CheckDefaultHotkeys()
    {
        if (ActiveHotkeyRegistrationState() is { } activeState)
        {
            return activeState;
        }

        var probe = hotkeyRegistrationProbe;
        if (probe is null && !OperatingSystem.IsWindows())
        {
            return OnboardingProbeState.Unchecked("Hotkey registration check requires user32.dll on Windows.");
        }

        probe ??= new Win32HotkeyRegistrationProbe();

        var registrations = ConfiguredHotkeyRegistrations();

        var registeredIds = new List<int>();
        try
        {
            foreach (var registration in registrations)
            {
                if (!probe.TryRegister(registration.Id, registration.Modifiers, registration.VirtualKey))
                {
                    return OnboardingProbeState.Blocked(
                        $"{registration.DisplayName} is already used by another app.",
                        actionKind: OnboardingActionKind.Configure,
                        actionLabel: "Change hotkeys");
                }

                registeredIds.Add(registration.Id);
            }

            return OnboardingProbeState.Available("Default hotkeys are ready.");
        }
        finally
        {
            UnregisterAll(probe, registeredIds);
        }
    }

    private OnboardingProbeState? ActiveHotkeyRegistrationState()
    {
        var activeResults = ActiveHotkeyRegistrations();
        if (activeResults is null || activeResults.Count == 0)
        {
            return null;
        }

        var failure = activeResults.FirstOrDefault(result => result.Status != HotkeyRegistrationStatus.Success);
        return failure is null
            ? OnboardingProbeState.Available("Configured hotkeys are ready.")
            : OnboardingProbeState.Blocked(
                failure.Message,
                actionKind: OnboardingActionKind.Configure,
                actionLabel: "Change hotkeys");
    }

    private IReadOnlyList<HotkeyRegistrationResult>? ActiveHotkeyRegistrations()
    {
        try
        {
            return activeHotkeyRegistrationsProvider?.Invoke();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException)
        {
            return null;
        }
    }

    private IReadOnlyList<HotkeyRegistration> ConfiguredHotkeyRegistrations()
    {
        try
        {
            return hotkeyBindingsProvider()
                .OrderBy(pair => pair.Key)
                .Select(pair => HotkeyRegistration.FromBinding(pair.Key, pair.Value))
                .ToArray();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException)
        {
            return HotkeyBinding.Defaults()
                .OrderBy(pair => pair.Key)
                .Select(pair => HotkeyRegistration.FromBinding(pair.Key, pair.Value))
                .ToArray();
        }
    }

    public async Task<OnboardingProbeState> CheckStartupAsync(CancellationToken cancellationToken = default)
    {
        var status = await startupTaskController.GetStatusAsync(cancellationToken).ConfigureAwait(false);
        return status.State switch
        {
            PingStartupTaskState.Enabled => OnboardingProbeState.Available(status.Message),
            PingStartupTaskState.EnabledByPolicy => OnboardingProbeState.Available(status.Message),
            PingStartupTaskState.Disabled => OnboardingProbeState.Available("Startup can be enabled in Settings."),
            PingStartupTaskState.DisabledByUser => OnboardingProbeState.Blocked(
                status.Message,
                SettingsLauncher.StartupAppsUri),
            PingStartupTaskState.DisabledByPolicy => OnboardingProbeState.Blocked(status.Message),
            _ => OnboardingProbeState.Unchecked(status.Message)
        };
    }

    public static string DefaultSupabaseDirectoryPath() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ping");

    public static string DefaultSupabaseConfigPath() =>
        Path.Combine(DefaultSupabaseDirectoryPath(), "Supabase.json");

    private static void UnregisterAll(IHotkeyRegistrationProbe probe, IEnumerable<int> ids)
    {
        foreach (var id in ids)
        {
            probe.Unregister(id);
        }
    }

    private sealed class Win32HotkeyRegistrationProbe : IHotkeyRegistrationProbe
    {
        public bool TryRegister(int id, uint modifiers, uint virtualKey) =>
            RegisterHotKey(IntPtr.Zero, id, modifiers, virtualKey);

        public void Unregister(int id) =>
            _ = UnregisterHotKey(IntPtr.Zero, id);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    }

    private sealed class WindowsElevationProbe : IElevationProbe
    {
        public bool IsElevated
        {
            get
            {
                if (!OperatingSystem.IsWindows())
                {
                    return false;
                }

#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
                try
                {
                    var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
                    var principal = new System.Security.Principal.WindowsPrincipal(identity);
                    return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
                }
                catch (System.Security.SecurityException)
                {
                    return false;
                }
                catch (UnauthorizedAccessException)
                {
                    return false;
                }
#else
                return false;
#endif
            }
        }
    }

    private sealed record HotkeyRegistration(
        int Id,
        uint Modifiers,
        uint VirtualKey,
        string DisplayName)
    {
        public static HotkeyRegistration FromBinding(HotkeyCommand command, HotkeyBinding binding) =>
            new(RegistrationId(command), binding.ToModifierFlags(), binding.ToVirtualKey(), binding.ToString());

        private static int RegistrationId(HotkeyCommand command) =>
            command switch
            {
                HotkeyCommand.FacePing => 'P',
                HotkeyCommand.ScreenFacePing => 'L',
                HotkeyCommand.QuickScreenFacePing => 1000 + 'L',
                HotkeyCommand.History => 'O',
                _ => throw new ArgumentOutOfRangeException(nameof(command), command, "Unknown hotkey command.")
            };
    }

    private sealed class NativeScreenCaptureSelfTest : INativeScreenCaptureSelfTest
    {
        public Task<OnboardingProbeState> CapturePrimaryMonitorFrameAsync(CancellationToken cancellationToken = default)
        {
            if (!OperatingSystem.IsWindows())
            {
                return Task.FromResult(OnboardingProbeState.Unchecked("Native screen capture self-test requires Windows."));
            }

            if (!NativeLibrary.TryLoad("Ping.Windows.NativeCapture.dll", out var library))
            {
                return Task.FromResult(OnboardingProbeState.Blocked("Native screen capture self-test bridge is unavailable."));
            }

            try
            {
                if (!NativeLibrary.TryGetExport(library, "PingScreenCaptureSelfTest", out var function))
                {
                    return Task.FromResult(OnboardingProbeState.Blocked("Native screen capture self-test export is missing."));
                }

                var selfTest = Marshal.GetDelegateForFunctionPointer<PingScreenCaptureSelfTestDelegate>(function);
                return Task.FromResult(selfTest() switch
                {
                    0 => OnboardingProbeState.Available("Screen capture self-test passed."),
                    1 => OnboardingProbeState.Unsupported("Graphics Capture is not supported on this device."),
                    2 => OnboardingProbeState.Blocked("Programmatic screen capture is blocked.", SettingsLauncher.GraphicsCapturePrivacyUri),
                    var code => OnboardingProbeState.Blocked($"Native screen capture self-test failed with code {code}.")
                });
            }
            finally
            {
                NativeLibrary.Free(library);
            }
        }

        [UnmanagedFunctionPointer(CallingConvention.Winapi)]
        private delegate int PingScreenCaptureSelfTestDelegate();
    }
}
