using Ping.Windows.App.Capture;
using Ping.Windows.App.Onboarding;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class CapturePreflightTests
{
    [Fact]
    public void FirstFailure_BlocksUnsupportedWindowsBeforePermissionChecks()
    {
        var failure = CapturePreflight.FirstFailure(
            CaptureMode.ScreenFace,
            WindowsSupportStatus.UnsupportedOldWindows11,
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available());

        Assert.NotNull(failure);
        Assert.Contains("Windows 11 24H2", failure!.Reason, StringComparison.Ordinal);
    }

    [Fact]
    public void FirstFailure_FaceOnlyIgnoresScreenCaptureState()
    {
        var failure = CapturePreflight.FirstFailure(
            CaptureMode.FaceOnly,
            WindowsSupportStatus.Supported,
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available(),
            OnboardingProbeState.Blocked("screen capture blocked"));

        Assert.Null(failure);
    }

    [Fact]
    public void FirstFailure_ScreenFaceRequiresScreenCapture()
    {
        var failure = CapturePreflight.FirstFailure(
            CaptureMode.ScreenFace,
            WindowsSupportStatus.Supported,
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available(),
            OnboardingProbeState.Blocked("screen capture blocked"));

        Assert.NotNull(failure);
        Assert.Contains("screen capture", failure!.Detail, StringComparison.Ordinal);
        Assert.Equal("screen capture blocked", failure.Reason);
    }

    [Fact]
    public void FirstFailure_ReportsCameraBeforeMicrophone()
    {
        var failure = CapturePreflight.FirstFailure(
            CaptureMode.ScreenFace,
            WindowsSupportStatus.Supported,
            OnboardingProbeState.Blocked("camera blocked"),
            OnboardingProbeState.Blocked("microphone blocked"),
            OnboardingProbeState.Available());

        Assert.NotNull(failure);
        Assert.Contains("camera", failure!.Detail, StringComparison.Ordinal);
        Assert.Equal("camera blocked", failure.Reason);
    }
}
