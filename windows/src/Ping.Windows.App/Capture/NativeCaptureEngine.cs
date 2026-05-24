using System.Runtime.InteropServices;

namespace Ping.Windows.App.Capture;

public enum PingCaptureErrorCode
{
    Success = 0,
    UnsupportedOs = 1,
    AccessDenied = 2,
    NoMonitor = 3,
    NoCamera = 4,
    EncoderFailure = 5,
    CaptureFailure = 6,
    ProtectedContent = 7,
    NoMicrophone = 8
}

public sealed record ScreenFaceCaptureResult(
    string FilePath,
    double AspectRatio);

public sealed record ScreenFacePreviewResult(
    string FilePath,
    double AspectRatio);

public sealed record ScreenCaptureSelfTestResult(
    bool IsSupported,
    PingCaptureErrorCode ErrorCode,
    string Message);

public interface IScreenFaceCaptureEngine
{
    Task<ScreenFaceCaptureResult> RecordAsync(
        TimeSpan duration,
        int monitorIndex,
        CancellationToken cancellationToken);

    Task<ScreenFacePreviewResult> CapturePreviewAsync(
        int monitorIndex,
        CancellationToken cancellationToken);

    Task<ScreenCaptureSelfTestResult> SelfTestAsync();
}

public sealed class NativeCaptureEngine : IScreenFaceCaptureEngine
{
    private const string NativeLibraryName = "Ping.Windows.NativeCapture.dll";
    private const double FaceDiameterRatio = 0.32;
    private static readonly string TemporaryDirectory = Path.Combine(Path.GetTempPath(), "Ping");

    public async Task<ScreenFaceCaptureResult> RecordAsync(
        TimeSpan duration,
        int monitorIndex,
        CancellationToken cancellationToken)
    {
        if (duration <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(duration), duration, "Recording duration must be positive.");
        }

        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(TemporaryDirectory);
        var outputPath = Path.Combine(
            TemporaryDirectory,
            $"screen-face-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}.mp4");

        double aspectRatio = 1;
        int result;
        try
        {
            result = await Task.Run(
                () => PingCapture_RecordScreenFaceMp4(
                    outputPath,
                    checked((int)Math.Round(duration.TotalMilliseconds)),
                    monitorIndex,
                    FaceDiameterRatio,
                    out aspectRatio),
                cancellationToken).ConfigureAwait(false);
        }
        catch (DllNotFoundException exception)
        {
            throw new PlatformNotSupportedException("Native screen capture DLL was not found.", exception);
        }
        catch (EntryPointNotFoundException exception)
        {
            throw new PlatformNotSupportedException("Native screen capture entry point is unavailable.", exception);
        }
        catch (BadImageFormatException exception)
        {
            throw new PlatformNotSupportedException("Native screen capture DLL architecture does not match this process.", exception);
        }

        cancellationToken.ThrowIfCancellationRequested();

        if (result != (int)PingCaptureErrorCode.Success)
        {
            TryDelete(outputPath);
            throw CreateException(result);
        }

        if (!File.Exists(outputPath) || new FileInfo(outputPath).Length == 0)
        {
            TryDelete(outputPath);
            throw new IOException("Native capture reported success but did not create a usable MP4.");
        }

        return new ScreenFaceCaptureResult(outputPath, NormalizeAspectRatio(aspectRatio));
    }

    public Task<ScreenCaptureSelfTestResult> SelfTestAsync()
    {
        try
        {
            return Task.FromResult(ToSelfTestResult(PingCapture_SelfTestScreenCapture()));
        }
        catch (DllNotFoundException exception)
        {
            return Task.FromResult(new ScreenCaptureSelfTestResult(
                false,
                PingCaptureErrorCode.UnsupportedOs,
                $"Native screen capture DLL was not found. {exception.Message}"));
        }
        catch (EntryPointNotFoundException exception)
        {
            return Task.FromResult(new ScreenCaptureSelfTestResult(
                false,
                PingCaptureErrorCode.UnsupportedOs,
                $"Native screen capture entry point is unavailable. {exception.Message}"));
        }
        catch (BadImageFormatException exception)
        {
            return Task.FromResult(new ScreenCaptureSelfTestResult(
                false,
                PingCaptureErrorCode.UnsupportedOs,
                $"Native screen capture DLL architecture does not match this process. {exception.Message}"));
        }
    }

    public async Task<ScreenFacePreviewResult> CapturePreviewAsync(
        int monitorIndex,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(TemporaryDirectory);
        var outputPath = Path.Combine(
            TemporaryDirectory,
            $"screen-preview-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}.bmp");

        double aspectRatio = 1;
        int result;
        try
        {
            result = await Task.Run(
                () => PingCapture_WriteScreenPreviewBmp(outputPath, monitorIndex, out aspectRatio),
                cancellationToken).ConfigureAwait(false);
        }
        catch (DllNotFoundException exception)
        {
            throw new PlatformNotSupportedException("Native screen capture DLL was not found.", exception);
        }
        catch (EntryPointNotFoundException exception)
        {
            throw new PlatformNotSupportedException("Native screen preview entry point is unavailable.", exception);
        }
        catch (BadImageFormatException exception)
        {
            throw new PlatformNotSupportedException("Native screen capture DLL architecture does not match this process.", exception);
        }

        cancellationToken.ThrowIfCancellationRequested();
        if (result != (int)PingCaptureErrorCode.Success)
        {
            TryDelete(outputPath);
            throw CreateException(result);
        }

        if (!File.Exists(outputPath) || new FileInfo(outputPath).Length == 0)
        {
            TryDelete(outputPath);
            throw new IOException("Native capture reported success but did not create a usable preview image.");
        }

        return new ScreenFacePreviewResult(outputPath, NormalizeAspectRatio(aspectRatio));
    }

    public static ScreenCaptureSelfTestResult ToSelfTestResult(int nativeCode)
    {
        var code = ToErrorCode(nativeCode);
        return new ScreenCaptureSelfTestResult(
            code == PingCaptureErrorCode.Success,
            code,
            code switch
            {
                PingCaptureErrorCode.Success => "Screen capture is available.",
                PingCaptureErrorCode.UnsupportedOs => "Screen capture is not supported on this Windows version.",
                PingCaptureErrorCode.AccessDenied => "Screen capture permission was denied.",
                PingCaptureErrorCode.NoMonitor => "No monitor was available for capture.",
                PingCaptureErrorCode.NoCamera => "No camera was available.",
                PingCaptureErrorCode.EncoderFailure => "The MP4 encoder could not be initialized.",
                PingCaptureErrorCode.CaptureFailure => "Screen capture failed.",
                PingCaptureErrorCode.ProtectedContent => "Screen capture returned protected content.",
                PingCaptureErrorCode.NoMicrophone => "No microphone was available.",
                _ => "Screen capture failed with an unknown error."
            });
    }

    public static Exception CreateException(int nativeCode)
    {
        var code = ToErrorCode(nativeCode);
        var message = $"Native screen-face capture failed with {code}.";
        return code switch
        {
            PingCaptureErrorCode.UnsupportedOs => new PlatformNotSupportedException(message),
            PingCaptureErrorCode.AccessDenied => new UnauthorizedAccessException(message),
            PingCaptureErrorCode.NoMonitor => new InvalidOperationException(message),
            PingCaptureErrorCode.NoCamera => new InvalidOperationException(message),
            PingCaptureErrorCode.EncoderFailure => new IOException(message),
            PingCaptureErrorCode.CaptureFailure => new IOException(message),
            PingCaptureErrorCode.ProtectedContent => new IOException(message),
            PingCaptureErrorCode.NoMicrophone => new InvalidOperationException(message),
            PingCaptureErrorCode.Success => new InvalidOperationException("Native capture success is not an exception."),
            _ => new IOException(message)
        };
    }

    private static PingCaptureErrorCode ToErrorCode(int nativeCode) =>
        Enum.IsDefined(typeof(PingCaptureErrorCode), nativeCode)
            ? (PingCaptureErrorCode)nativeCode
            : PingCaptureErrorCode.CaptureFailure;

    private static double NormalizeAspectRatio(double aspectRatio)
    {
        if (double.IsNaN(aspectRatio) || double.IsInfinity(aspectRatio) || aspectRatio <= 0)
        {
            return 16.0 / 9.0;
        }

        return aspectRatio;
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    [DllImport(NativeLibraryName, CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_RecordScreenFaceMp4(
        string outputPath,
        int durationMs,
        int targetMonitorIndex,
        double faceDiameterRatio,
        out double outAspectRatio);

    [DllImport(NativeLibraryName, CallingConvention = CallingConvention.Winapi, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_SelfTestScreenCapture();

    [DllImport(NativeLibraryName, CallingConvention = CallingConvention.Winapi, CharSet = CharSet.Unicode, ExactSpelling = true)]
    [DefaultDllImportSearchPaths(DllImportSearchPath.ApplicationDirectory)]
    private static extern int PingCapture_WriteScreenPreviewBmp(
        string outputPath,
        int targetMonitorIndex,
        out double outAspectRatio);
}
