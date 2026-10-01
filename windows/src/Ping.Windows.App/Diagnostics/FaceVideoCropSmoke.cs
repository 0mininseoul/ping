#if PING_UI_SMOKE
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI;
using Ping.Windows.App.Capture;
using Windows.Graphics.Imaging;
using Windows.Media.Editing;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

internal static class FaceVideoCropSmoke
{
    internal static async Task RunAsync(string output, Action<bool, string> check)
    {
        var folder = await StorageFolder.GetFolderFromPathAsync(output);
        var image = await folder.CreateFileAsync("owned-face-bands.png", CreationCollisionOption.FailIfExists);
        using (var stream = await image.OpenAsync(FileAccessMode.ReadWrite))
        {
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            var bytes = new byte[320 * 192 * 4];
            for (var y = 0; y < 192; y++) for (var x = 0; x < 320; x++)
            {
                var index = (y * 320 + x) * 4;
                bytes[index] = x >= 256 ? (byte)255 : (byte)0;
                bytes[index + 1] = x >= 64 && x < 256 ? (byte)255 : (byte)0;
                bytes[index + 2] = x < 64 ? (byte)255 : (byte)0;
                bytes[index + 3] = 255;
            }
            encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, 320, 192, 96, 96, bytes);
            await encoder.FlushAsync();
        }
        var wavePath = Path.Combine(output, "owned-face-audio.wav");
        using (var writer = new BinaryWriter(File.Create(wavePath)))
        {
            writer.Write(System.Text.Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + 48000 * 3 * 2);
            writer.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt ")); writer.Write(16); writer.Write((ushort)1); writer.Write((ushort)1);
            writer.Write(48000); writer.Write(96000); writer.Write((ushort)2); writer.Write((ushort)16);
            writer.Write(System.Text.Encoding.ASCII.GetBytes("data")); writer.Write(48000 * 3 * 2);
            for (var index = 0; index < 48000 * 3; index++) writer.Write((short)(5000 * Math.Sin(index * 440 * 2 * Math.PI / 48000)));
        }
        var composition = new MediaComposition();
        composition.Clips.Add(await MediaClip.CreateFromImageFileAsync(image, TimeSpan.FromSeconds(3)));
        composition.BackgroundAudioTracks.Add(await BackgroundAudioTrack.CreateFromFileAsync(await StorageFile.GetFileFromPathAsync(wavePath)));
        var source = await folder.CreateFileAsync("owned-face-source.mp4", CreationCollisionOption.FailIfExists);
        var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.Wvga);
        profile.Video.Width = 320; profile.Video.Height = 192; profile.Video.Bitrate = 400000;
        profile.Audio.SampleRate = 48000; profile.Audio.ChannelCount = 1; profile.Audio.Bitrate = 64000;
        var rendered = await composition.RenderToFileAsync(source, MediaTrimmingPreference.Precise, profile);
        check(rendered == TranscodeFailureReason.None, "owned face color bands and audio encoded without capture hardware");
        var sourceProfile = await MediaEncodingProfile.CreateFromFileAsync(source);
        File.WriteAllText(Path.Combine(output, "face-source-profile.json"), System.Text.Json.JsonSerializer.Serialize(new
        {
            sourceProfile.Video.Width, sourceProfile.Video.Height, sourceProfile.Video.Bitrate,
            FrameNumerator = sourceProfile.Video.FrameRate.Numerator, FrameDenominator = sourceProfile.Video.FrameRate.Denominator,
            Container = sourceProfile.Container.Subtype, Video = sourceProfile.Video.Subtype,
            Audio = sourceProfile.Audio.Subtype, sourceProfile.Audio.SampleRate, sourceProfile.Audio.BitsPerSample,
            sourceProfile.Audio.ChannelCount, AudioBitrate = sourceProfile.Audio.Bitrate
        }));

        var path = await FaceVideoCropper.CropToSquareAsync(source.Path, CancellationToken.None);
        try
        {
            var square = await StorageFile.GetFileFromPathAsync(path);
            var encoded = await MediaEncodingProfile.CreateFromFileAsync(square);
            File.WriteAllText(Path.Combine(output, "face-square-profile.json"), System.Text.Json.JsonSerializer.Serialize(new
            {
                encoded.Video.Width, encoded.Video.Height, Video = encoded.Video.Subtype,
                Audio = encoded.Audio?.Subtype, ExpectedAudio = MediaEncodingSubtypes.Aac,
                encoded.Audio?.SampleRate, encoded.Audio?.ChannelCount, encoded.Audio?.Bitrate
            }));
            check(encoded.Video.Width == 192 && encoded.Video.Height == 192 && encoded.Video.Subtype == MediaEncodingSubtypes.H264,
                "actual face exporter produces square H264 video");
            check(encoded.Audio is { ChannelCount: 1, SampleRate: 48000 }
                && string.Equals(encoded.Audio.Subtype, MediaEncodingSubtypes.Aac, StringComparison.OrdinalIgnoreCase),
                "actual face exporter preserves mono AAC audio");
            var metadata = await square.Properties.GetVideoPropertiesAsync();
            check(Math.Abs(metadata.Duration.TotalSeconds - 3) < .15, "actual face exporter preserves three-second duration");
            var result = new MediaComposition(); result.Clips.Add(await MediaClip.CreateFromFileAsync(square));
            using var thumbnail = await result.GetThumbnailAsync(TimeSpan.FromSeconds(1), 192, 192, VideoFramePrecision.NearestFrame);
            var decoder = await BitmapDecoder.CreateAsync(thumbnail);
            var pixels = (await decoder.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore,
                new BitmapTransform(), ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage)).DetachPixelData();
            var left = (96 * 192 + 30) * 4; var right = (96 * 192 + 160) * 4;
            check(pixels[left + 1] > 170 && pixels[left + 2] < 70 && pixels[right + 1] > 170 && pixels[right] < 70,
                "decoded face export retains center band instead of squeezing outside edges into square");
        }
        finally { File.Delete(path); }
    }
}
#endif

