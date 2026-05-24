using System.Runtime.InteropServices;

namespace Ping.Windows.App.Onboarding;

public interface INativeScreenCaptureSelfTest
{
    Task<OnboardingProbeState> CapturePrimaryMonitorFrameAsync(CancellationToken cancellationToken = default);
}

public sealed class PermissionProbe
{
    private readonly string supabaseConfigPath;
    private readonly INativeScreenCaptureSelfTest screenCaptureSelfTest;

    public PermissionProbe(
        string? supabaseConfigPath = null,
        INativeScreenCaptureSelfTest? screenCaptureSelfTest = null)
    {
        this.supabaseConfigPath = supabaseConfigPath ?? DefaultSupabaseConfigPath();
        this.screenCaptureSelfTest = screenCaptureSelfTest ?? new NativeScreenCaptureSelfTest();
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
            CheckStartup());

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
        if (!OperatingSystem.IsWindows())
        {
            return OnboardingProbeState.Unchecked("Hotkey registration check requires user32.dll on Windows.");
        }

        var registrations = new[]
        {
            HotkeyRegistration.Alt('P'),
            HotkeyRegistration.Alt('L'),
            HotkeyRegistration.AltShift('L'),
            HotkeyRegistration.Alt('O')
        };

        foreach (var registration in registrations)
        {
            if (!TryRegisterHotKey(registration))
            {
                return OnboardingProbeState.Blocked(
                    $"{registration.DisplayName} is already used by another app.",
                    actionKind: OnboardingActionKind.Configure,
                    actionLabel: "Change hotkeys");
            }
        }

        return OnboardingProbeState.Available("Default hotkeys are ready.");
    }

    public OnboardingProbeState CheckStartup()
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        return OnboardingProbeState.Unchecked("Startup registration will be checked after MSIX startup task wiring is added.");
#else
        return OnboardingProbeState.Unchecked("Startup toggle is available only in packaged Windows builds.");
#endif
    }

    public static string DefaultSupabaseDirectoryPath() =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ping");

    public static string DefaultSupabaseConfigPath() =>
        Path.Combine(DefaultSupabaseDirectoryPath(), "Supabase.json");

    private static bool TryRegisterHotKey(HotkeyRegistration hotkey)
    {
        if (!RegisterHotKey(IntPtr.Zero, hotkey.Id, hotkey.Modifiers, hotkey.VirtualKey))
        {
            return false;
        }

        _ = UnregisterHotKey(IntPtr.Zero, hotkey.Id);
        return true;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    private sealed record HotkeyRegistration(
        int Id,
        uint Modifiers,
        uint VirtualKey,
        string DisplayName)
    {
        private const uint ModAlt = 0x0001;
        private const uint ModShift = 0x0004;

        public static HotkeyRegistration Alt(char key) =>
            new(key, ModAlt, key, $"Alt+{key}");

        public static HotkeyRegistration AltShift(char key) =>
            new(1000 + key, ModAlt | ModShift, key, $"Alt+Shift+{key}");
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
