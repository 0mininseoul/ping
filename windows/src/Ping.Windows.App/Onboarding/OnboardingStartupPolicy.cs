using Ping.Windows.App.Hotkeys;

namespace Ping.Windows.App.Onboarding;

public static class OnboardingStartupPolicy
{
    public static bool ShouldOpen(
        WindowsSupportStatus windowsStatus,
        bool isSupabaseConfigured,
        bool isElevated,
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

        if (isElevated)
        {
            return true;
        }

        return hotkeyRegistrations.Any(result => result.Status != HotkeyRegistrationStatus.Success);
    }
}
