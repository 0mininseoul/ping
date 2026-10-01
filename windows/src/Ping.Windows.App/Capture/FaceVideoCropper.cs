using Windows.Foundation;
using Windows.Media.Editing;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;

namespace Ping.Windows.App.Capture;

internal static class FaceVideoCropper
{
    internal static async Task<string> CropToSquareAsync(string sourcePath, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var source = await CaptureWinRtOperation.WaitAsync(StorageFile.GetFileFromPathAsync(sourcePath), token);
        var sourceProfile = await CaptureWinRtOperation.WaitAsync(MediaEncodingProfile.CreateFromFileAsync(source), token);
        token.ThrowIfCancellationRequested();
        var sourceVideo = sourceProfile.Video ?? throw new IOException("얼굴 영상에 비디오가 없습니다.");
        var width = sourceVideo.Width; var height = sourceVideo.Height;
        var side = Math.Min(width, height) & ~1u;
        if (side < 2) throw new IOException("얼굴 영상의 크기를 확인할 수 없습니다.");
        var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD720p);
        var video = profile.Video;
        video.Width = side; video.Height = side; video.Bitrate = 1_200_000;
        video.FrameRate.Numerator = sourceVideo.FrameRate.Numerator;
        video.FrameRate.Denominator = sourceVideo.FrameRate.Denominator;
        video.PixelAspectRatio.Numerator = 1; video.PixelAspectRatio.Denominator = 1;
        if (sourceProfile.Audio is { } audio)
        {
            profile.Audio.SampleRate = audio.SampleRate;
            profile.Audio.ChannelCount = audio.ChannelCount;
            profile.Audio.Bitrate = 64_000;
        }
        else profile.Audio = null;
        var folder = await CaptureWinRtOperation.WaitAsync(StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(sourcePath)!), token);
        token.ThrowIfCancellationRequested();
        var output = await CaptureWinRtOperation.WaitAsync(folder.CreateFileAsync($"face-square-{Guid.NewGuid():N}.mp4", CreationCollisionOption.FailIfExists), token);
        try
        {
            token.ThrowIfCancellationRequested();
            var composition = new MediaComposition();
            var clip = await CaptureWinRtOperation.WaitAsync(MediaClip.CreateFromFileAsync(source), token);
            token.ThrowIfCancellationRequested();
            composition.Clips.Add(MediaClip.CreateFromColor(Microsoft.UI.Colors.Black, clip.OriginalDuration));
            var layer = new MediaOverlayLayer();
            layer.Overlays.Add(new MediaOverlay(clip,
                new Rect((side - (double)width) / 2, (side - (double)height) / 2, width, height), 1) { AudioEnabled = true });
            composition.OverlayLayers.Add(layer);
            var operation = composition.RenderToFileAsync(output, MediaTrimmingPreference.Precise, profile);
            TranscodeFailureReason result;
            try { result = await CaptureWinRtOperation.WaitAsync(operation, token); }
            finally { operation.Close(); }
            token.ThrowIfCancellationRequested();
            if (result != TranscodeFailureReason.None) throw new IOException($"얼굴 영상을 정사각형으로 저장할 수 없습니다: {result}");
            return output.Path;
        }
        catch
        {
            try { File.Delete(output.Path); } catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            throw;
        }
    }
}
