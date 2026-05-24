using Ping.Windows.App.Hotkeys;

namespace Ping.Windows.App.Onboarding;

public static class OnboardingStartupPolicy
{
    public static bool ShouldOpen(
        WindowsSupportStatus windowsStatus,
        bool isSupabaseConfigured,
        IReadOnlyList<HotkeyRegistrationResult> hotkeyRegistrations)
    {
        if (windowsStatus != WindowsSupportStatus.Supported)
        {
            return true;
        }

        if (!isSupabaseConfigured)
        {
            return true;
        }

        return hotkeyRegistrations.Any(result => result.Status != HotkeyRegistrationStatus.Success);
    }
}
