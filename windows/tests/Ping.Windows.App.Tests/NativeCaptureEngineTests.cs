using Ping.Windows.App.Capture;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class NativeCaptureEngineTests
{
    [Fact]
    public void ScreenFaceCompositor_UsesMacLayoutRatios()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.NativeCapture",
            "src",
            "ScreenFaceCompositor.cpp"));

        Assert.Contains("DefaultFaceDiameterRatio = 0.32", source, StringComparison.Ordinal);
        Assert.Contains("DefaultPaddingRatio = 0.045", source, StringComparison.Ordinal);
        Assert.DoesNotContain("PipMarginPixels", source, StringComparison.Ordinal);
    }

    [Fact]
    public void NativeCaptureEngine_CapturesThirtyFramesPerSecond()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.NativeCapture",
            "src",
            "PingCaptureEngine.cpp"));

        Assert.Contains("CaptureFramesPerSecond = 30", source, StringComparison.Ordinal);
        Assert.DoesNotContain("CaptureFramesPerSecond = 15", source, StringComparison.Ordinal);
    }

    [Fact]
    public void NativeCaptureProject_DisablesWindowsMinMaxMacrosAndSerializesPdbWrites()
    {
        var project = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.NativeCapture",
            "Ping.Windows.NativeCapture.vcxproj"));

        Assert.Contains("NOMINMAX", project, StringComparison.Ordinal);
        Assert.Contains("/FS", project, StringComparison.Ordinal);
    }

    [Fact]
    public void MonitorCapture_UsesFullyQualifiedWinRtWindowsNamespaces()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.NativeCapture",
            "src",
            "MonitorCapture.cpp"));

        Assert.Contains("using namespace winrt::Windows::Graphics::Capture;", source, StringComparison.Ordinal);
        Assert.Contains("using namespace winrt::Windows::Graphics::DirectX;", source, StringComparison.Ordinal);
        Assert.Contains("using namespace winrt::Windows::Graphics::DirectX::Direct3D11;", source, StringComparison.Ordinal);
        Assert.DoesNotContain("using namespace Windows::Graphics", source, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(PingCaptureErrorCode.Success, true)]
    [InlineData(PingCaptureErrorCode.UnsupportedOs, false)]
    [InlineData(PingCaptureErrorCode.AccessDenied, false)]
    [InlineData(PingCaptureErrorCode.NoMonitor, false)]
    [InlineData(PingCaptureErrorCode.NoCamera, false)]
    [InlineData(PingCaptureErrorCode.EncoderFailure, false)]
    [InlineData(PingCaptureErrorCode.CaptureFailure, false)]
    [InlineData(PingCaptureErrorCode.ProtectedContent, false)]
    [InlineData(PingCaptureErrorCode.NoMicrophone, false)]
    public void SelfTestResult_MapsNativeErrorCode(PingCaptureErrorCode code, bool expectedSupported)
    {
        var result = NativeCaptureEngine.ToSelfTestResult((int)code);

        Assert.Equal(code, result.ErrorCode);
        Assert.Equal(expectedSupported, result.IsSupported);
        Assert.False(string.IsNullOrWhiteSpace(result.Message));
    }

    [Fact]
    public void SelfTestResult_SuccessMentionsCaptureBorderAndProtectedContent()
    {
        var result = NativeCaptureEngine.ToSelfTestResult((int)PingCaptureErrorCode.Success);

        Assert.Contains("capture border", result.Message, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("protected content", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData(PingCaptureErrorCode.UnsupportedOs, typeof(PlatformNotSupportedException))]
    [InlineData(PingCaptureErrorCode.AccessDenied, typeof(UnauthorizedAccessException))]
    [InlineData(PingCaptureErrorCode.NoMonitor, typeof(InvalidOperationException))]
    [InlineData(PingCaptureErrorCode.NoCamera, typeof(InvalidOperationException))]
    [InlineData(PingCaptureErrorCode.EncoderFailure, typeof(IOException))]
    [InlineData(PingCaptureErrorCode.CaptureFailure, typeof(IOException))]
    [InlineData(PingCaptureErrorCode.ProtectedContent, typeof(IOException))]
    [InlineData(PingCaptureErrorCode.NoMicrophone, typeof(InvalidOperationException))]
    public void CreateException_MapsNativeErrorCode(PingCaptureErrorCode code, Type expectedType)
    {
        var exception = NativeCaptureEngine.CreateException((int)code);

        Assert.IsType(expectedType, exception);
        Assert.Contains(code.ToString(), exception.Message, StringComparison.Ordinal);
    }

    [Fact]
    public async Task CanceledNativeCapture_DeletesCompletedTemporaryOutput()
    {
        var tempPath = Path.Combine(Path.GetTempPath(), "PingWindowsTests", $"{Guid.NewGuid():N}.mp4");
        Directory.CreateDirectory(Path.GetDirectoryName(tempPath)!);
        await File.WriteAllBytesAsync(tempPath, [0x00, 0x01]);
        using var cancellation = new CancellationTokenSource();
        await cancellation.CancelAsync();

        Assert.Throws<OperationCanceledException>(() =>
            NativeCaptureEngine.ThrowIfCanceledAndDeleteOutput(cancellation.Token, tempPath));
        Assert.False(File.Exists(tempPath));
    }

    private static string RepoRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "PING_PROJECT_SPECIFICATION.md")))
        {
            directory = directory.Parent;
        }

        return directory?.FullName
            ?? throw new DirectoryNotFoundException("Could not locate Ping repository root.");
    }
}
