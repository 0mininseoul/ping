using Ping.Windows.App.Capture;

namespace Ping.Windows.App.Tests;

public sealed class NativeCaptureEngineTests
{
    [Theory]
    [InlineData(PingCaptureErrorCode.Success, true)]
    [InlineData(PingCaptureErrorCode.UnsupportedOs, false)]
    [InlineData(PingCaptureErrorCode.AccessDenied, false)]
    [InlineData(PingCaptureErrorCode.NoMonitor, false)]
    [InlineData(PingCaptureErrorCode.NoCamera, false)]
    [InlineData(PingCaptureErrorCode.EncoderFailure, false)]
    [InlineData(PingCaptureErrorCode.CaptureFailure, false)]
    public void SelfTestResult_MapsNativeErrorCode(PingCaptureErrorCode code, bool expectedSupported)
    {
        var result = NativeCaptureEngine.ToSelfTestResult((int)code);

        Assert.Equal(code, result.ErrorCode);
        Assert.Equal(expectedSupported, result.IsSupported);
        Assert.False(string.IsNullOrWhiteSpace(result.Message));
    }

    [Theory]
    [InlineData(PingCaptureErrorCode.UnsupportedOs, typeof(PlatformNotSupportedException))]
    [InlineData(PingCaptureErrorCode.AccessDenied, typeof(UnauthorizedAccessException))]
    [InlineData(PingCaptureErrorCode.NoMonitor, typeof(InvalidOperationException))]
    [InlineData(PingCaptureErrorCode.NoCamera, typeof(InvalidOperationException))]
    [InlineData(PingCaptureErrorCode.EncoderFailure, typeof(IOException))]
    [InlineData(PingCaptureErrorCode.CaptureFailure, typeof(IOException))]
    public void CreateException_MapsNativeErrorCode(PingCaptureErrorCode code, Type expectedType)
    {
        var exception = NativeCaptureEngine.CreateException((int)code);

        Assert.IsType(expectedType, exception);
        Assert.Contains(code.ToString(), exception.Message, StringComparison.Ordinal);
    }
}
