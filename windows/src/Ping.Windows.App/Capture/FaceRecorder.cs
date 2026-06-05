#if WINDOWS
using Windows.Media.Capture;
using Windows.Media.MediaProperties;
using Windows.Storage;
using Microsoft.UI.Xaml.Controls;
#endif

namespace Ping.Windows.App.Capture;

public sealed class FaceRecorder : IFaceRecorder
{
    private static readonly string TemporaryDirectory = Path.Combine(Path.GetTempPath(), "Ping");
    private MediaCapture? previewCapture;
    private CaptureElement? previewElement;
    private bool isPreviewCaptureInitialized;
    private bool isPreviewing;

    public async Task<FaceRecordingResult> RecordAsync(
        TimeSpan duration,
        CancellationToken cancellationToken = default)
    {
        if (duration <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(duration), duration, "Recording duration must be positive.");
        }

#if WINDOWS
        Directory.CreateDirectory(TemporaryDirectory);
        var file = await CreateOutputFileAsync(cancellationToken).ConfigureAwait(false);
        var filePath = file.Path;
        var capture = isPreviewCaptureInitialized ? previewCapture : null;
        var ownsCapture = capture is null;
        LowLagMediaRecording? recording = null;

        try
        {
            if (capture is null)
            {
                capture = new MediaCapture();
                await capture.InitializeAsync(new MediaCaptureInitializationSettings
                {
                    StreamingCaptureMode = StreamingCaptureMode.AudioAndVideo
                });
            }

            var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
            profile.Video.Subtype = MediaEncodingSubtypes.H264;
            profile.Audio.Subtype = MediaEncodingSubtypes.Aac;

            recording = await capture.PrepareLowLagRecordToStorageFileAsync(profile, file);
            await recording.StartAsync();
            await Task.Delay(duration, cancellationToken).ConfigureAwait(false);
            await recording.StopAsync();
            await recording.FinishAsync();

            return new FaceRecordingResult(filePath, duration);
        }
        catch
        {
            if (recording is not null)
            {
                try
                {
                    await recording.StopAsync();
                }
                catch (Exception)
                {
                }

                try
                {
                    await recording.FinishAsync();
                }
                catch (Exception)
                {
                }
            }

            TryDelete(filePath);
            throw;
        }
        finally
        {
            if (ownsCapture)
            {
                capture?.Dispose();
            }
        }
#else
        _ = cancellationToken;
        await Task.CompletedTask.ConfigureAwait(false);
        throw new PlatformNotSupportedException("Face recording requires Windows MediaCapture on a Windows target framework.");
#endif
    }

#if WINDOWS
    public async Task StartPreviewAsync(CaptureElement preview, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(preview);
        cancellationToken.ThrowIfCancellationRequested();
        var capture = previewCapture ?? new MediaCapture();
        previewCapture = capture;
        try
        {
            if (!isPreviewCaptureInitialized)
            {
                await capture.InitializeAsync(new MediaCaptureInitializationSettings
                {
                    StreamingCaptureMode = StreamingCaptureMode.AudioAndVideo
                });
                isPreviewCaptureInitialized = true;
            }

            cancellationToken.ThrowIfCancellationRequested();
            preview.Source = capture;
            await capture.StartPreviewAsync();
            previewElement = preview;
            isPreviewing = true;
        }
        catch
        {
            preview.Source = null;
            previewElement = null;
            previewCapture?.Dispose();
            previewCapture = null;
            isPreviewCaptureInitialized = false;
            isPreviewing = false;
            throw;
        }
    }

    public async Task StopPreviewAsync(CaptureElement preview)
    {
        try
        {
            if (isPreviewing && previewCapture is not null)
            {
                await previewCapture.StopPreviewAsync();
            }
        }
        catch (Exception)
        {
        }
        finally
        {
            preview.Source = null;
            if (previewElement is not null && !ReferenceEquals(previewElement, preview))
            {
                previewElement.Source = null;
            }

            previewElement = null;
            previewCapture?.Dispose();
            previewCapture = null;
            isPreviewCaptureInitialized = false;
            isPreviewing = false;
        }
    }
#endif

#if WINDOWS
    private static async Task<StorageFile> CreateOutputFileAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var folder = await StorageFolder.GetFolderFromPathAsync(TemporaryDirectory);
        cancellationToken.ThrowIfCancellationRequested();
        return await folder.CreateFileAsync(
            $"face-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss-fff}-{Guid.NewGuid():N}.mp4",
            CreationCollisionOption.FailIfExists);
    }
#endif

    private static void TryDelete(string filePath)
    {
        try
        {
            if (File.Exists(filePath))
            {
                File.Delete(filePath);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
