#if PING_UI_SMOKE
using Microsoft.UI.Xaml.Controls;
using Ping.Windows.App.Capture;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Diagnostics;

internal static class CaptureLifetimeSmoke
{
    public static async Task RunAsync(Action<bool, string> check)
    {
        var camera = new CameraOwnership();
        var room = new Room("capture-room", "친구", "친구", "me", ["me", "peer"], new Dictionary<string, string>(), RoomStatus.Open);
        var faceLease = camera.TryAcquire(CameraPurpose.Manual)!;
        var faceModel = new FaceMirrorViewModel(new([room], "me", "나", "친구", false, false), new NoFaceCapture(), (_, _) => Task.CompletedTask);
        var face = new FaceMirrorWindow(faceModel, faceLease);
        face.Activate();
        await Task.Delay(100);
        try
        {
            CaptureMirrorSmoke.Verify(face, false, faceModel.MirrorPosition, check);
            await CaptureMirrorSmoke.VerifyWorkAreaRefreshAsync(face, check);
        }
        finally { face.Close(); await face.CameraShutdown; }
        await Task.Delay(80);
        check(!camera.IsBusy, "real face mirror closes once and releases camera ownership without initialization");

        var lease = camera.TryAcquire(CameraPurpose.Manual)!;
        var preview = new DelayedPreview();
        var engine = new NoScreenCapture();
        var model = new ScreenFaceMirrorViewModel(new([room], "me", "나", "친구", false, false), engine, (_, _) => Task.CompletedTask);
        var screen = new ScreenFaceMirrorWindow(model, lease, _ => preview);
        screen.Activate();
        await preview.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var enter = screen.HandleEnterAsync();
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (preview.Stops == 0 && DateTime.UtcNow < deadline) await Task.Delay(10);
        check(preview.Stops == 1, "delayed preview owns pending native camera shutdown");
        var secondEnter = screen.HandleEnterAsync();
        try
        {
            CaptureMirrorSmoke.Verify(screen, true, model.MirrorPosition, check);
            await CaptureMirrorSmoke.VerifyWorkAreaRefreshAsync(screen, check);
            check(engine.Recordings == 0, "repeated Enter cannot record while old preview still owns camera");
            screen.Close();
            await Task.Delay(80);
            check(camera.IsBusy && !screen.CameraShutdown.IsCompleted,
                "real screen mirror close waits for already pending preview shutdown");
            check(engine.Recordings == 0, "native screen recording cannot overlap pending preview initialization");
        }
        finally
        {
            preview.Finish();
            await enter;
            await secondEnter;
            if (!model.IsCloseRequested) screen.Close();
            await screen.CameraShutdown;
        }
        check(!camera.IsBusy && preview.Stops == 1,
            "real screen mirror shares one preview stop and releases lease after cleanup");
    }

    private sealed class NoFaceCapture : IFaceRecorder
    {
        public Task<FaceRecordingResult> RecordAsync(TimeSpan duration, CancellationToken cancellationToken = default) => throw new InvalidOperationException("Fixture does not capture camera.");
    }
    private sealed class NoScreenCapture : IScreenFaceCaptureEngine
    {
        public int Recordings;
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, CancellationToken token)
        { ++Recordings; return Task.FromException<ScreenFaceCaptureResult>(new InvalidOperationException("Fixture must not capture screen.")); }
        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitor, CancellationToken token) => Task.FromException<ScreenFacePreviewResult>(new IOException("Fixture has no screen content."));
        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => throw new NotSupportedException();
    }
    private sealed class DelayedPreview : IFacePreviewSession
    {
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource finished = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int Stops;
        public Task StartPreviewAsync(MediaPlayerElement element, CancellationToken token = default) { Started.TrySetResult(); return finished.Task; }
        public async Task StopPreviewAsync(MediaPlayerElement element) { ++Stops; await finished.Task; }
        public void Finish() => finished.TrySetResult();
    }
}
#endif
