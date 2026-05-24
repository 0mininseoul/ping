#if WINDOWS
using Windows.Media.Capture;
using Windows.Media.MediaProperties;
using Windows.Storage;
#endif

namespace Ping.Windows.App.Capture;

public sealed class FaceRecorder : IFaceRecorder
{
    private static readonly string TemporaryDirectory = Path.Combine(Path.GetTempPath(), "Ping");

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
        MediaCapture? capture = null;
        LowLagMediaRecording? recording = null;

        try
        {
            capture = new MediaCapture();
            await capture.InitializeAsync(new MediaCaptureInitializationSettings
            {
                StreamingCaptureMode = StreamingCaptureMode.AudioAndVideo
            });

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
            capture?.Dispose();
        }
#else
        _ = cancellationToken;
        await Task.CompletedTask.ConfigureAwait(false);
        throw new PlatformNotSupportedException("Face recording requires Windows MediaCapture on a Windows target framework.");
#endif
    }

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
