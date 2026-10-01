#if PING_UI_SMOKE
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Composition;
using Ping.Windows.App.Capture;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Diagnostics;

internal static class CaptureMirrorReviewSmoke
{
    internal static async Task RunAsync(string output, Action<bool, string> check, Func<FrameworkElement, string, Task> render)
    {
        var room = new Room("capture-room", "친구", "친구", "me", ["me", "peer"], new Dictionary<string, string>(), RoomStatus.Open);
        var original = Path.Combine(output, "synthetic-playback.mp4");
        var facePath = Path.Combine(output, "synthetic-face-review.mp4"); File.Copy(original, facePath);
        var camera = new CameraOwnership();
        var faceModel = new FaceMirrorViewModel(new([room], "me", "나", "친구", false, false), new FaceClip(facePath),
            (_, _) => Task.FromException(new IOException("Owned upload failure.")));
        var face = new FaceMirrorWindow(faceModel, camera.TryAcquire(CameraPurpose.Manual)!);
        try
        {
            face.Activate(); await Task.Delay(80);
            await faceModel.HandleEnterAsync(); await Task.Delay(120);
            var review = (MediaPlayerElement)((FrameworkElement)face.Content).FindName("ReviewElement");
            check(faceModel.State == MirrorState.Reviewing && review.Visibility == Visibility.Visible && review.MediaPlayer is not null,
                "real face mirror attaches actual review player to owned synthetic clip");
            await VerifyPlaybackAsync(review, check);
            VerifyClip((FrameworkElement)face.Content, true, check);
            await render((FrameworkElement)face.Content, "capture-face-review.png");
            await faceModel.HandleEnterAsync();
            check(faceModel.State == MirrorState.Failed && review.Visibility == Visibility.Visible && review.MediaPlayer is not null,
                "real face mirror keeps review visible after failed upload");
            check(review.MediaPlayer?.Source is not null && File.Exists(facePath), "failed face upload retains owned clip for retry");
        }
        finally { face.Close(); await face.CameraShutdown; }
        check(!camera.IsBusy && !File.Exists(facePath), "real face review close disposes player and removes temporary clip");

        var screenPath = Path.Combine(output, "synthetic-screen-review.mp4"); File.Copy(original, screenPath);
        var screenModel = new ScreenFaceMirrorViewModel(new([room], "me", "나", "친구", false, false), new ScreenClip(screenPath),
            (_, _) => Task.FromException(new IOException("Owned upload failure.")));
        var screen = new ScreenFaceMirrorWindow(screenModel, camera.TryAcquire(CameraPurpose.Manual)!, _ => new NoPreview());
        try
        {
            screen.Activate(); await Task.Delay(80);
            await screen.HandleEnterAsync(); await Task.Delay(120);
            var review = (MediaPlayerElement)((FrameworkElement)screen.Content).FindName("ReviewElement");
            check(screenModel.State == MirrorState.Reviewing && review.Visibility == Visibility.Visible && review.MediaPlayer is not null,
                "real screen mirror attaches actual review player to owned synthetic clip");
            await VerifyPlaybackAsync(review, check);
            VerifyClip((FrameworkElement)screen.Content, false, check);
            await render((FrameworkElement)screen.Content, "capture-screen-review.png");
            await screen.HandleEnterAsync();
            check(screenModel.State == MirrorState.Failed && review.Visibility == Visibility.Visible && review.MediaPlayer is not null,
                "real screen mirror keeps review visible after failed upload");
            check(review.MediaPlayer?.Source is not null && File.Exists(screenPath), "failed screen upload retains owned clip for retry");
        }
        finally { screen.Close(); await screen.CameraShutdown; }
        check(!camera.IsBusy && !File.Exists(screenPath), "real screen review close disposes player and removes temporary clip");
    }

    private static void VerifyClip(FrameworkElement root, bool face, Action<bool, string> check)
    {
        var clip = ElementCompositionPreview.GetElementVisual(root).Clip as CompositionGeometricClip;
        var geometry = clip?.Geometry as CompositionRoundedRectangleGeometry;
        check(geometry is not null && Math.Abs(geometry.Size.X - root.Width) < .1
            && Math.Abs(geometry.Size.Y - root.Height) < .1 && Math.Abs(geometry.CornerRadius.X - (face ? root.Width / 2 : 16)) < .1,
            "real mirror composition clip follows current circular or16DIP rounded surface");
    }
    private static async Task VerifyPlaybackAsync(MediaPlayerElement element, Action<bool, string> check)
    {
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (DateTime.UtcNow < deadline)
        {
            var session = element.MediaPlayer.PlaybackSession;
            if (session.NaturalVideoWidth > 0 && session.NaturalVideoHeight > 0 && session.Position > TimeSpan.FromMilliseconds(20))
            {
                check(true, "actual mirror review opens synthetic video metadata and advances playback clock");
                return;
            }
            await Task.Delay(10);
        }
        check(false, "actual mirror review opens synthetic video metadata and advances playback clock");
    }
    private sealed class FaceClip(string path) : IFaceRecorder
    {
        public Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default) => Task.FromResult(new FaceRecordingResult(path, duration));
    }
    private sealed class ScreenClip(string path) : IScreenFaceCaptureEngine
    {
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitorIndex, CancellationToken cancellationToken) => Task.FromResult(new ScreenFaceCaptureResult(path, 16d / 9));
        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitorIndex, CancellationToken cancellationToken) => Task.FromException<ScreenFacePreviewResult>(new IOException("Owned fixture has no screen input."));
        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => throw new NotSupportedException();
    }
    private sealed class NoPreview : IFacePreviewSession
    {
        public Task StartPreviewAsync(MediaPlayerElement element, CancellationToken token = default) => Task.CompletedTask;
        public Task StopPreviewAsync(MediaPlayerElement element) => Task.CompletedTask;
    }
}
#endif
