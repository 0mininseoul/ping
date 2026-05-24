using Ping.Windows.App.Onboarding;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Capture;

public sealed record CapturePreflightFailure(
    string Detail,
    string Reason);

public static class CapturePreflight
{
    public static CapturePreflightFailure? FirstFailure(
        CaptureMode mode,
        WindowsSupportStatus windowsStatus,
        OnboardingProbeState camera,
        OnboardingProbeState microphone,
        OnboardingProbeState screenCapture)
    {
        if (windowsStatus != WindowsSupportStatus.Supported)
        {
            return new CapturePreflightFailure(
                "this Windows version is not supported for recording.",
                WindowsReason(windowsStatus));
        }

        if (camera.Status != OnboardingProbeStatus.Available)
        {
            return new CapturePreflightFailure(
                "camera access is not ready.",
                camera.Message);
        }

        if (microphone.Status != OnboardingProbeStatus.Available)
        {
            return new CapturePreflightFailure(
                "microphone access is not ready.",
                microphone.Message);
        }

        if (mode == CaptureMode.ScreenFace && screenCapture.Status != OnboardingProbeStatus.Available)
        {
            return new CapturePreflightFailure(
                "screen capture access is not ready.",
                screenCapture.Message);
        }

        return null;
    }

    private static string WindowsReason(WindowsSupportStatus windowsStatus) => windowsStatus switch
    {
        WindowsSupportStatus.UnsupportedWindows10 => "Windows 10 is not a supported target for Ping Windows.",
        WindowsSupportStatus.UnsupportedOldWindows11 => "Windows 11 24H2 or newer is required for screen, camera, and notification parity.",
        WindowsSupportStatus.Supported => "Windows is supported.",
        _ => "Windows 11 24H2 or newer is required for Ping Windows."
    };
}
