using Ping.Windows.Core.Capture;

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
    NoMicrophone = 8,
    Cancelled = 9
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

    Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, ScreenCaptureViewport viewport,
        CancellationToken cancellationToken) => throw new NotSupportedException("Capture engine does not support viewport recording.");
    Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, ScreenCaptureViewport viewport,
        CancellationToken cancellationToken) => throw new NotSupportedException("Capture engine does not support viewport preview.");
}

public interface ICameraBoundScreenCaptureEngine
{
    Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, ScreenCaptureViewport viewport,
        string cameraDeviceId, CancellationToken token);
}

public sealed class NativeCaptureEngine(INativeScreenCaptureApi? nativeApi = null) : IScreenFaceCaptureEngine, ICameraBoundScreenCaptureEngine
{
    private readonly INativeScreenCaptureApi api = nativeApi ?? new NativeScreenCaptureApi();
    private const double FaceDiameterRatio = 0.32;
    private static readonly string TemporaryDirectory = Path.Combine(Path.GetTempPath(), "Ping");

    public Task<ScreenFaceCaptureResult> RecordAsync(
        TimeSpan duration,
        int monitorIndex,
        CancellationToken cancellationToken) => RecordAsync(duration, monitorIndex, new ScreenCaptureViewport(), cancellationToken);

    public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex,
        ScreenCaptureViewport viewport, CancellationToken cancellationToken)
        => RecordCoreAsync(duration, monitorIndex, viewport, null, cancellationToken);

    public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, ScreenCaptureViewport viewport,
        string cameraDeviceId, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(cameraDeviceId) || cameraDeviceId.Contains('\0'))
            throw new ArgumentException("A selected camera identity is required.", nameof(cameraDeviceId));
        return RecordCoreAsync(duration, monitorIndex, viewport, cameraDeviceId, token);
    }

    private async Task<ScreenFaceCaptureResult> RecordCoreAsync(TimeSpan duration, int monitorIndex,
        ScreenCaptureViewport viewport, string? cameraDeviceId, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(viewport);
        if (duration <= TimeSpan.Zero || duration > TimeSpan.FromSeconds(30))
        {
            throw new ArgumentOutOfRangeException(nameof(duration), duration, "Recording duration must be positive and at most30seconds.");
        }

        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(TemporaryDirectory);
        var outputPath = Path.Combine(
            TemporaryDirectory,
            $"screen-face-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}.mp4");
        using var nativeCancellation = new EventWaitHandle(false, EventResetMode.ManualReset);
        using var cancellationRegistration = cancellationToken.Register(() => nativeCancellation.Set());

        double aspectRatio = 1;
        int result;
        try
        {
            result = await Task.Run(
                () => cameraDeviceId is null ? api.Record(
                    outputPath,
                    checked((int)Math.Round(duration.TotalMilliseconds)),
                    monitorIndex,
                    FaceDiameterRatio,
                    viewport,
                    nativeCancellation.SafeWaitHandle,
                    out aspectRatio) : api.Record(outputPath, checked((int)Math.Round(duration.TotalMilliseconds)),
                        monitorIndex, FaceDiameterRatio, viewport, cameraDeviceId, nativeCancellation.SafeWaitHandle, out aspectRatio),
                cancellationToken).ConfigureAwait(false);
        }
        catch (DllNotFoundException exception)
        {
            TryDelete(outputPath);
            throw new PlatformNotSupportedException("Native screen capture DLL was not found.", exception);
        }
        catch (EntryPointNotFoundException exception)
        {
            TryDelete(outputPath);
            throw new PlatformNotSupportedException("Native screen capture entry point is unavailable.", exception);
        }
        catch (BadImageFormatException exception)
        {
            TryDelete(outputPath);
            throw new PlatformNotSupportedException("Native screen capture DLL architecture does not match this process.", exception);
        }
        catch { TryDelete(outputPath); throw; }

        ThrowIfCanceledAndDeleteOutput(cancellationToken, outputPath);

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

    public async Task<ScreenCaptureSelfTestResult> SelfTestAsync()
    {
        try
        {
            return ToSelfTestResult(await Task.Run(api.SelfTest).ConfigureAwait(false));
        }
        catch (DllNotFoundException exception)
        {
            return new ScreenCaptureSelfTestResult(
                false,
                PingCaptureErrorCode.UnsupportedOs,
                $"Native screen capture DLL was not found. {exception.Message}");
        }
        catch (EntryPointNotFoundException exception)
        {
            return new ScreenCaptureSelfTestResult(
                false,
                PingCaptureErrorCode.UnsupportedOs,
                $"Native screen capture entry point is unavailable. {exception.Message}");
        }
        catch (BadImageFormatException exception)
        {
            return new ScreenCaptureSelfTestResult(
                false,
                PingCaptureErrorCode.UnsupportedOs,
                $"Native screen capture DLL architecture does not match this process. {exception.Message}");
        }
    }

    public Task<ScreenFacePreviewResult> CapturePreviewAsync(
        int monitorIndex,
        CancellationToken cancellationToken) => CapturePreviewAsync(monitorIndex, new ScreenCaptureViewport(), cancellationToken);

    public async Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, ScreenCaptureViewport viewport,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(viewport);
        cancellationToken.ThrowIfCancellationRequested();
        Directory.CreateDirectory(TemporaryDirectory);
        var outputPath = Path.Combine(
            TemporaryDirectory,
            $"screen-preview-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}.bmp");
        using var nativeCancellation = new EventWaitHandle(false, EventResetMode.ManualReset);
        using var cancellationRegistration = cancellationToken.Register(() => nativeCancellation.Set());

        double aspectRatio = 1;
        int result;
        try
        {
            result = await Task.Run(
                () => api.Preview(outputPath, monitorIndex, viewport, nativeCancellation.SafeWaitHandle, out aspectRatio),
                cancellationToken).ConfigureAwait(false);
        }
        catch (DllNotFoundException exception)
        {
            TryDelete(outputPath);
            throw new PlatformNotSupportedException("Native screen capture DLL was not found.", exception);
        }
        catch (EntryPointNotFoundException exception)
        {
            TryDelete(outputPath);
            throw new PlatformNotSupportedException("Native screen preview entry point is unavailable.", exception);
        }
        catch (BadImageFormatException exception)
        {
            TryDelete(outputPath);
            throw new PlatformNotSupportedException("Native screen capture DLL architecture does not match this process.", exception);
        }
        catch { TryDelete(outputPath); throw; }

        ThrowIfCanceledAndDeleteOutput(cancellationToken, outputPath);
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
                PingCaptureErrorCode.Success => "Screen capture is available. Windows may show a capture border and protected content may not be sent.",
                PingCaptureErrorCode.UnsupportedOs => "Screen capture is not supported on this Windows version.",
                PingCaptureErrorCode.AccessDenied => "Screen capture permission was denied.",
                PingCaptureErrorCode.NoMonitor => "No monitor was available for capture.",
                PingCaptureErrorCode.NoCamera => "No camera was available.",
                PingCaptureErrorCode.EncoderFailure => "The MP4 encoder could not be initialized.",
                PingCaptureErrorCode.CaptureFailure => "Screen capture failed.",
                PingCaptureErrorCode.ProtectedContent => "Screen capture returned protected content.",
                PingCaptureErrorCode.NoMicrophone => "No microphone was available.",
                PingCaptureErrorCode.Cancelled => "Capture was cancelled.",
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
            PingCaptureErrorCode.Cancelled => new OperationCanceledException(message),
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

    internal static void ThrowIfCanceledAndDeleteOutput(CancellationToken cancellationToken, string outputPath)
    {
        if (!cancellationToken.IsCancellationRequested)
        {
            return;
        }

        TryDelete(outputPath);
        cancellationToken.ThrowIfCancellationRequested();
    }

}
