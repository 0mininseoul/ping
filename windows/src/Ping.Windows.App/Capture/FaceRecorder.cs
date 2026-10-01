using Ping.Windows.Core.Capture;
using Windows.Media.Capture;
using Windows.Media.Capture.Frames;
using Windows.Media.Core;
using Windows.Media.MediaProperties;
using Windows.Media.Playback;
using Windows.Storage;
using Microsoft.UI.Xaml.Controls;

namespace Ping.Windows.App.Capture;

public sealed class FaceRecorder : IFaceRecorder, IFacePreviewSession, IAsyncDisposable
{
    private static readonly string TemporaryDirectory = Path.Combine(Path.GetTempPath(), "Ping");
    private readonly CameraDeviceSession<MediaCapture> session;
    private MediaPlayer? previewPlayer;

    public FaceRecorder(CameraLease lease)
    {
        session = new(lease, token => InitializeAsync(lease, token), capture =>
        {
            try { previewPlayer?.Dispose(); }
            finally { previewPlayer = null; capture.Dispose(); }
            return ValueTask.CompletedTask;
        });
    }

    private static async Task<MediaCapture> InitializeAsync(CameraLease lease, CancellationToken token)
    {
        var cameraDeviceId = await lease.CameraSelection.GetAsync(CaptureCameraResolver.ResolveAsync, token);
        var microphone = await lease.MicrophoneSelection.GetAsync(CaptureMicrophoneResolver.ResolveAsync, token);
        var capture = new MediaCapture();
        try
        {
            await CaptureWinRtOperation.WaitAsync(capture.InitializeAsync(new MediaCaptureInitializationSettings
            {
                StreamingCaptureMode = StreamingCaptureMode.AudioAndVideo,
                VideoDeviceId = cameraDeviceId,
                AudioDeviceId = microphone.WinRtId
            }), token);
            return capture;
        }
        catch { capture.Dispose(); throw; }
    }

    public Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default)
    {
        if (duration <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(duration));
        return session.UseAsync((capture, token) => RecordCoreAsync(capture, duration, token), cancellationToken);
    }

    private static async Task<FaceRecordingResult> RecordCoreAsync(MediaCapture capture, TimeSpan duration, CancellationToken token)
    {
        Directory.CreateDirectory(TemporaryDirectory);
        var folder = await CaptureWinRtOperation.WaitAsync(StorageFolder.GetFolderFromPathAsync(TemporaryDirectory), token);
        token.ThrowIfCancellationRequested();
        var file = await CaptureWinRtOperation.WaitAsync(folder.CreateFileAsync($"face-{Guid.NewGuid():N}.mp4", CreationCollisionOption.FailIfExists), token);
        LowLagMediaRecording? recording = null;
        var finished = false;
        try
        {
            token.ThrowIfCancellationRequested();
            var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD720p);
            profile.Video.Subtype = MediaEncodingSubtypes.H264;
            profile.Audio.Subtype = MediaEncodingSubtypes.Aac;
            recording = await CaptureWinRtOperation.WaitAsync(capture.PrepareLowLagRecordToStorageFileAsync(profile, file), token);
            token.ThrowIfCancellationRequested();
            await CaptureWinRtOperation.WaitAsync(recording.StartAsync(), token);
            await Task.Delay(duration, token);
            await recording.StopAsync();
            await recording.FinishAsync();
            finished = true;
            token.ThrowIfCancellationRequested();
            var squarePath = await FaceVideoCropper.CropToSquareAsync(file.Path, token);
            TryDelete(file.Path);
            return new(squarePath, duration);
        }
        catch
        {
            if (recording is not null && !finished)
            {
                try { await recording.StopAsync(); } catch { }
                try { await recording.FinishAsync(); } catch { }
            }
            TryDelete(file.Path);
            throw;
        }
    }

    public Task StartPreviewAsync(MediaPlayerElement preview, CancellationToken cancellationToken = default) =>
        session.UseAsync((capture, token) =>
        {
            token.ThrowIfCancellationRequested();
            var source = capture.FrameSources.Values.FirstOrDefault(frame => frame.Info.SourceKind == MediaFrameSourceKind.Color
                && frame.Info.MediaStreamType == MediaStreamType.VideoPreview)
                ?? capture.FrameSources.Values.FirstOrDefault(frame => frame.Info.SourceKind == MediaFrameSourceKind.Color
                    && frame.Info.MediaStreamType == MediaStreamType.VideoRecord)
                ?? throw new InvalidOperationException("카메라 미리보기를 사용할 수 없습니다.");
            previewPlayer?.Dispose();
            previewPlayer = new() { RealTimePlayback = true, Source = MediaSource.CreateFromMediaFrameSource(source) };
            preview.SetMediaPlayer(previewPlayer);
            previewPlayer.Play();
            return Task.FromResult(true);
        }, cancellationToken);

    public async Task StopPreviewAsync(MediaPlayerElement preview)
    {
        try { preview.SetMediaPlayer(null); }
        finally { await session.DisposeAsync(); }
    }

    public ValueTask DisposeAsync() => session.DisposeAsync();

    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}
