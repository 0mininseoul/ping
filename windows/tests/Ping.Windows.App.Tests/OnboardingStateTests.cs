using Ping.Windows.App.Onboarding;
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
        Assert.Equal(OnboardingActionKind.OpenFolder, row.PrimaryAction?.Kind);
        Assert.Equal("Open config folder", row.PrimaryAction?.Label);
        Assert.True(row.CanRetry);
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
}
