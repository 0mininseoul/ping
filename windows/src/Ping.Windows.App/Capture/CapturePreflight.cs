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
                "이 Windows 버전에서는 촬영할 수 없어요.",
                WindowsReason(windowsStatus));
        }

        if (camera.Status != OnboardingProbeStatus.Available)
        {
            return new CapturePreflightFailure(
                "카메라를 사용할 수 없어요. 연결과 촬영 기기 설정을 확인해 주세요.",
                camera.Message);
        }

        if (microphone.Status != OnboardingProbeStatus.Available)
        {
            return new CapturePreflightFailure(
                "마이크를 사용할 수 없어요. 연결과 촬영 기기 설정을 확인해 주세요.",
                microphone.Message);
        }

        if (mode == CaptureMode.ScreenFace && screenCapture.Status != OnboardingProbeStatus.Available)
        {
            return new CapturePreflightFailure(
                "화면을 촬영할 수 없어요. Windows 화면 캡처 권한을 확인해 주세요.",
                screenCapture.Message);
        }

        return null;
    }

    private static string WindowsReason(WindowsSupportStatus windowsStatus) => windowsStatus switch
    {
        WindowsSupportStatus.UnsupportedWindows10 => "촬영에는 Windows 11 24H2 이상이 필요해요.",
        WindowsSupportStatus.UnsupportedOldWindows11 => "Windows 업데이트에서 Windows 11 24H2 이상으로 업데이트해 주세요.",
        WindowsSupportStatus.Supported => "지원하는 Windows 버전이에요.",
        _ => "Ping은 Windows 11 24H2 이상을 지원해요."
    };
}
