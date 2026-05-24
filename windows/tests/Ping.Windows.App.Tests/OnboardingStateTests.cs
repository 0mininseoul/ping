using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Onboarding;
using Ping.Windows.App.Setup;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class OnboardingStateTests
{
    [Theory]
    [InlineData(10, 0, 19045, WindowsSupportStatus.UnsupportedWindows10)]
    [InlineData(10, 0, 22631, WindowsSupportStatus.UnsupportedOldWindows11)]
    [InlineData(10, 0, 26100, WindowsSupportStatus.Supported)]
    public void WindowsVersionProbe_maps_supported_and_unsupported_builds(
        int major,
        int minor,
        int build,
        WindowsSupportStatus expected)
    {
        var actual = WindowsVersionProbe.StatusFor(new Version(major, minor, build));

        Assert.Equal(expected, actual);
    }

    [Fact]
    public void Supported_environment_enables_screen_face_quick_send()
    {
        var state = OnboardingEnvironmentState.Ready() with
        {
            WindowsStatus = WindowsSupportStatus.Supported
        };

        var model = new OnboardingViewModel(state);

        Assert.True(model.IsScreenFaceQuickSendEnabled);
        Assert.Equal("Screen+face quick send is ready for Alt+Shift+L.", model.ScreenFaceQuickSendStatusText);
        Assert.All(model.Rows, row => Assert.Equal(OnboardingRowStatus.Ready, row.Status));
    }

    [Theory]
    [InlineData(WindowsSupportStatus.UnsupportedWindows10, "Windows 10 is not a supported target for Ping Windows.")]
    [InlineData(WindowsSupportStatus.UnsupportedOldWindows11, "Windows 11 24H2 or newer is required for full support.")]
    public void Unsupported_windows_versions_disable_screen_face_quick_send(
        WindowsSupportStatus windowsStatus,
        string expectedMessage)
    {
        var model = new OnboardingViewModel(OnboardingEnvironmentState.Ready() with
        {
            WindowsStatus = windowsStatus
        });

        var row = Assert.Single(model.Rows, row => row.Kind == OnboardingRowKind.WindowsVersion);
        Assert.Equal(OnboardingRowStatus.Warning, row.Status);
        Assert.Equal(expectedMessage, row.Message);
        Assert.Null(row.PrimaryAction);
        Assert.False(model.IsScreenFaceQuickSendEnabled);
        Assert.Equal("Screen+face quick send is disabled until Windows 11 24H2+ is ready.", model.ScreenFaceQuickSendStatusText);
    }

    [Fact]
    public void Camera_or_microphone_block_disables_screen_face_quick_send()
    {
        var cameraBlocked = new OnboardingViewModel(OnboardingEnvironmentState.Ready() with
        {
            Camera = OnboardingProbeState.Blocked("Camera access is blocked.", SettingsLauncher.WebcamPrivacyUri)
        });
        var microphoneBlocked = new OnboardingViewModel(OnboardingEnvironmentState.Ready() with
        {
            Microphone = OnboardingProbeState.Blocked("Microphone access is blocked.", SettingsLauncher.MicrophonePrivacyUri)
        });

        Assert.False(cameraBlocked.IsScreenFaceQuickSendEnabled);
        Assert.False(microphoneBlocked.IsScreenFaceQuickSendEnabled);
        Assert.Equal("Screen+face quick send is disabled until camera access is ready.", cameraBlocked.ScreenFaceQuickSendStatusText);
        Assert.Equal("Screen+face quick send is disabled until microphone access is ready.", microphoneBlocked.ScreenFaceQuickSendStatusText);
    }

    [Fact]
    public void Blocked_permissions_map_to_settings_and_retry_ctas()
    {
        var model = new OnboardingViewModel(OnboardingEnvironmentState.Ready() with
        {
            Camera = OnboardingProbeState.Blocked("Camera access is blocked.", SettingsLauncher.WebcamPrivacyUri),
            Microphone = OnboardingProbeState.Blocked("Microphone access is blocked.", SettingsLauncher.MicrophonePrivacyUri),
            ScreenCapture = OnboardingProbeState.Blocked("Programmatic screen capture is blocked.", SettingsLauncher.GraphicsCapturePrivacyUri),
            Notifications = OnboardingProbeState.Blocked("Notifications are blocked.", SettingsLauncher.NotificationsPrivacyUri),
            Hotkeys = OnboardingProbeState.Blocked("Alt+P is already used by another app.", actionKind: OnboardingActionKind.Configure, actionLabel: "Change hotkeys")
        });

        AssertSettingsAction(model, OnboardingRowKind.Camera, SettingsLauncher.WebcamPrivacyUri);
        AssertSettingsAction(model, OnboardingRowKind.Microphone, SettingsLauncher.MicrophonePrivacyUri);
        AssertSettingsAction(model, OnboardingRowKind.ScreenCapture, SettingsLauncher.GraphicsCapturePrivacyUri);
        AssertSettingsAction(model, OnboardingRowKind.Notifications, SettingsLauncher.NotificationsPrivacyUri);

        var hotkeys = Assert.Single(model.Rows, row => row.Kind == OnboardingRowKind.Hotkeys);
        Assert.Equal(OnboardingRowStatus.Blocked, hotkeys.Status);
        Assert.True(hotkeys.CanRetry);
        Assert.Equal(OnboardingActionKind.Configure, hotkeys.PrimaryAction?.Kind);
        Assert.Equal("Change hotkeys", hotkeys.PrimaryAction?.Label);
        Assert.False(model.IsScreenFaceQuickSendEnabled);
    }

    [Fact]
    public void Missing_supabase_config_maps_to_open_config_action()
    {
        var model = new OnboardingViewModel(OnboardingEnvironmentState.Ready() with
        {
            IsSupabaseConfigured = false
        });

        var row = Assert.Single(model.Rows, row => row.Kind == OnboardingRowKind.SupabaseConfig);
        Assert.Equal(OnboardingRowStatus.Blocked, row.Status);
        Assert.Equal("Missing or invalid Supabase.json in the Ping local config folder.", row.Message);
        Assert.True(row.HasPrimaryAction);
        Assert.Equal("Open config folder", row.PrimaryActionLabel);
        Assert.Equal(OnboardingActionKind.OpenFolder, row.PrimaryAction?.Kind);
        Assert.Equal("Open config folder", row.PrimaryAction?.Label);
        Assert.True(row.CanRetry);
        Assert.False(model.IsScreenFaceQuickSendEnabled);
        Assert.Equal("Screen+face quick send is disabled until Supabase config is ready.", model.ScreenFaceQuickSendStatusText);
    }

    [Fact]
    public void StartupPolicy_opens_onboarding_for_missing_config_or_hotkey_conflicts()
    {
        Assert.True(OnboardingStartupPolicy.ShouldOpen(
            WindowsSupportStatus.Supported,
            isSupabaseConfigured: false,
            [HotkeyRegistrationResult.Success(HotkeyCommand.FacePing, HotkeyBinding.Alt("P"))]));
        Assert.True(OnboardingStartupPolicy.ShouldOpen(
            WindowsSupportStatus.Supported,
            isSupabaseConfigured: true,
            [HotkeyRegistrationResult.Conflict(HotkeyCommand.FacePing, HotkeyBinding.Alt("P"), "used")]));
        Assert.True(OnboardingStartupPolicy.ShouldOpen(
            WindowsSupportStatus.UnsupportedOldWindows11,
            isSupabaseConfigured: true,
            [HotkeyRegistrationResult.Success(HotkeyCommand.FacePing, HotkeyBinding.Alt("P"))]));
        Assert.False(OnboardingStartupPolicy.ShouldOpen(
            WindowsSupportStatus.Supported,
            isSupabaseConfigured: true,
            [HotkeyRegistrationResult.Success(HotkeyCommand.FacePing, HotkeyBinding.Alt("P"))]));
    }

    [Fact]
    public void PermissionProbe_detects_valid_supabase_config_file()
    {
        var directory = Path.Combine(Path.GetTempPath(), "PingWindowsOnboardingTests", Guid.NewGuid().ToString("N"));
        var configPath = Path.Combine(directory, "Supabase.json");
        Directory.CreateDirectory(directory);
        try
        {
            var probe = new PermissionProbe(configPath);
            Assert.False(probe.IsSupabaseConfigured());

            File.WriteAllText(configPath, """
                {
                  "url": "https://example.supabase.co",
                  "anonKey": "anon-key"
                }
                """);

            Assert.True(probe.IsSupabaseConfigured());
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Theory]
    [InlineData("{}")]
    [InlineData("{not-json")]
    public void PermissionProbe_rejects_invalid_supabase_config_file(string configJson)
    {
        var directory = Path.Combine(Path.GetTempPath(), "PingWindowsOnboardingTests", Guid.NewGuid().ToString("N"));
        var configPath = Path.Combine(directory, "Supabase.json");
        Directory.CreateDirectory(directory);
        try
        {
            File.WriteAllText(configPath, configJson);
            var probe = new PermissionProbe(configPath);

            Assert.False(probe.IsSupabaseConfigured());
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public async Task PermissionProbe_runtime_checks_are_explicitly_unchecked_in_portable_tests()
    {
        var probe = new PermissionProbe(Path.Combine(Path.GetTempPath(), "missing-supabase.json"));

        Assert.Equal(OnboardingProbeStatus.Unchecked, (await probe.CheckCameraAsync()).Status);
        Assert.Equal(OnboardingProbeStatus.Unchecked, (await probe.CheckMicrophoneAsync()).Status);
        Assert.Equal(OnboardingProbeStatus.Unchecked, (await probe.CheckScreenCaptureAsync()).Status);
        Assert.Equal(OnboardingProbeStatus.Unchecked, (await probe.CheckNotificationsAsync()).Status);
    }

    [Fact]
    public async Task PermissionProbe_blocks_notifications_when_process_is_elevated()
    {
        var probe = new PermissionProbe(
            Path.Combine(Path.GetTempPath(), "missing-supabase.json"),
            elevationProbe: new FixedElevationProbe(isElevated: true));

        var state = await probe.CheckNotificationsAsync();

        Assert.Equal(OnboardingProbeStatus.Blocked, state.Status);
        Assert.Equal(OnboardingActionKind.Relaunch, state.ActionKind);
        Assert.Equal("Restart normally", state.ActionLabel);
    }

    [Fact]
    public void PermissionProbe_unregisters_probe_hotkeys_when_later_registration_conflicts()
    {
        var hotkeys = new RecordingHotkeyProbe(conflictingId: 'L');
        var probe = new PermissionProbe(
            Path.Combine(Path.GetTempPath(), "missing-supabase.json"),
            hotkeyRegistrationProbe: hotkeys);

        var state = probe.CheckDefaultHotkeys();

        Assert.Equal(OnboardingProbeStatus.Blocked, state.Status);
        Assert.Equal(new[] { (int)'P', (int)'L' }, hotkeys.RegisteredIds);
        Assert.Equal(new[] { (int)'P' }, hotkeys.UnregisteredIds);
    }

    [Fact]
    public void PermissionProbe_checks_configured_hotkeys_instead_of_defaults()
    {
        var hotkeys = new RecordingHotkeyProbe(conflictingId: -1);
        var probe = new PermissionProbe(
            Path.Combine(Path.GetTempPath(), "missing-supabase.json"),
            hotkeyRegistrationProbe: hotkeys,
            hotkeyBindingsProvider: () => new Dictionary<HotkeyCommand, HotkeyBinding>
            {
                [HotkeyCommand.FacePing] = HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Shift, "F"),
                [HotkeyCommand.ScreenFacePing] = HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Alt, "S"),
                [HotkeyCommand.QuickScreenFacePing] = HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Shift, "Q"),
                [HotkeyCommand.History] = HotkeyBinding.Alt("O")
            });

        var state = probe.CheckDefaultHotkeys();

        Assert.Equal(OnboardingProbeStatus.Available, state.Status);
        Assert.Contains((uint)'F', hotkeys.RegisteredVirtualKeys);
        Assert.Contains((uint)'S', hotkeys.RegisteredVirtualKeys);
        Assert.Contains((uint)'Q', hotkeys.RegisteredVirtualKeys);
        Assert.DoesNotContain((uint)'P', hotkeys.RegisteredVirtualKeys);
        Assert.Equal(hotkeys.RegisteredIds, hotkeys.UnregisteredIds);
    }

    [Fact]
    public void PermissionProbe_uses_active_hotkey_registrations_without_reprobing()
    {
        var hotkeys = new RecordingHotkeyProbe(conflictingId: -1);
        var probe = new PermissionProbe(
            Path.Combine(Path.GetTempPath(), "missing-supabase.json"),
            hotkeyRegistrationProbe: hotkeys,
            activeHotkeyRegistrationsProvider: () =>
            [
                HotkeyRegistrationResult.Success(HotkeyCommand.FacePing, HotkeyBinding.Alt("P")),
                HotkeyRegistrationResult.Success(HotkeyCommand.ScreenFacePing, HotkeyBinding.Alt("L")),
                HotkeyRegistrationResult.Success(HotkeyCommand.QuickScreenFacePing, HotkeyBinding.FromParts(HotkeyModifiers.Alt | HotkeyModifiers.Shift, "L")),
                HotkeyRegistrationResult.Success(HotkeyCommand.History, HotkeyBinding.Alt("O"))
            ]);

        var state = probe.CheckDefaultHotkeys();

        Assert.Equal(OnboardingProbeStatus.Available, state.Status);
        Assert.Equal("Configured hotkeys are ready.", state.Message);
        Assert.Empty(hotkeys.RegisteredIds);
    }

    [Fact]
    public void PermissionProbe_maps_active_hotkey_registration_conflicts_to_configure_action()
    {
        var hotkeys = new RecordingHotkeyProbe(conflictingId: -1);
        var probe = new PermissionProbe(
            Path.Combine(Path.GetTempPath(), "missing-supabase.json"),
            hotkeyRegistrationProbe: hotkeys,
            activeHotkeyRegistrationsProvider: () =>
            [
                HotkeyRegistrationResult.Success(HotkeyCommand.FacePing, HotkeyBinding.Alt("P")),
                HotkeyRegistrationResult.Conflict(
                    HotkeyCommand.ScreenFacePing,
                    HotkeyBinding.Alt("L"),
                    "Alt+L is already used by another app.")
            ]);

        var state = probe.CheckDefaultHotkeys();

        Assert.Equal(OnboardingProbeStatus.Blocked, state.Status);
        Assert.Equal("Alt+L is already used by another app.", state.Message);
        Assert.Equal(OnboardingActionKind.Configure, state.ActionKind);
        Assert.Equal("Change hotkeys", state.ActionLabel);
        Assert.Empty(hotkeys.RegisteredIds);
    }

    [Fact]
    public async Task PermissionProbe_maps_user_disabled_startup_to_windows_settings()
    {
        var probe = new PermissionProbe(
            Path.Combine(Path.GetTempPath(), "missing-supabase.json"),
            startupTaskController: new FixedStartupTaskController(new PingStartupTaskStatus(
                PingStartupTaskState.DisabledByUser,
                "Startup was disabled in Windows Settings.")));

        var state = await probe.CheckStartupAsync();

        Assert.Equal(OnboardingProbeStatus.Blocked, state.Status);
        Assert.Equal(SettingsLauncher.StartupAppsUri, state.SettingsUri);
    }

    private static void AssertSettingsAction(
        OnboardingViewModel model,
        OnboardingRowKind kind,
        string expectedUri)
    {
        var row = Assert.Single(model.Rows, row => row.Kind == kind);
        Assert.Equal(OnboardingRowStatus.Blocked, row.Status);
        Assert.True(row.CanRetry);
        Assert.Equal(OnboardingActionKind.Settings, row.PrimaryAction?.Kind);
        Assert.Equal(expectedUri, row.PrimaryAction?.Uri);
        Assert.Equal("Open settings", row.PrimaryAction?.Label);
    }

    private sealed class RecordingHotkeyProbe(int conflictingId) : IHotkeyRegistrationProbe
    {
        public List<int> RegisteredIds { get; } = [];

        public List<int> UnregisteredIds { get; } = [];

        public List<uint> RegisteredVirtualKeys { get; } = [];

        public bool TryRegister(int id, uint modifiers, uint virtualKey)
        {
            _ = modifiers;
            RegisteredIds.Add(id);
            RegisteredVirtualKeys.Add(virtualKey);
            return id != conflictingId;
        }

        public void Unregister(int id)
        {
            UnregisteredIds.Add(id);
        }
    }

    private sealed class FixedStartupTaskController(PingStartupTaskStatus status) : IStartupTaskController
    {
        public Task<PingStartupTaskStatus> GetStatusAsync(CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            return Task.FromResult(status);
        }

        public Task<PingStartupTaskStatus> SetEnabledAsync(bool isEnabled, CancellationToken cancellationToken = default)
        {
            _ = isEnabled;
            _ = cancellationToken;
            return Task.FromResult(status);
        }
    }

    private sealed class FixedElevationProbe(bool isElevated) : IElevationProbe
    {
        public bool IsElevated { get; } = isElevated;
    }
}
