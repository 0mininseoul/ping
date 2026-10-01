using Microsoft.Win32.SafeHandles;
using Ping.Windows.App.Capture;
using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class LiveCapturePreviewTests
{
    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task PreviewUsesSelectedDevicesAndKeepsLeaseAndHandleUntilNativeReturn(bool cancel)
    {
        var api = new Api();
        var camera = new CameraOwnership();
        var microphone = new CaptureMicrophoneDevice("winrt-microphone", "endpoint-microphone");
        var engine = new OwnedScreenFaceCaptureEngine(camera, new NativeCaptureEngine(api),
            selectCamera: _ => Task.FromResult("selected-camera"), selectMicrophone: _ => Task.FromResult(microphone));
        var frames = new List<CapturePreviewFrame>();
        using var cancellation = new CancellationTokenSource();
        var viewport = new ScreenCaptureViewport(2, .6, .4);
        var recording = engine.RecordAsync(TimeSpan.FromSeconds(3), 2, viewport, frames.Add, cancellation.Token);
        try
        {
            await api.Entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Assert.Equal(("selected-camera", "endpoint-microphone", 2, viewport), api.Selection);
            Assert.True(camera.IsBusy);
            if (cancel) cancellation.Cancel();
            Assert.False(recording.IsCompleted);
            Assert.False(api.Handle!.IsClosed);
            api.Complete.TrySetResult();
            if (cancel) await Assert.ThrowsAnyAsync<OperationCanceledException>(() => recording);
            else
            {
                var result = await recording;
                Assert.Equal(api.Path, result.FilePath);
                Assert.True(File.Exists(result.FilePath));
            }
            Assert.Single(frames);
            Assert.Equal(255, frames[0].Pixels.Span[1]);
            Assert.False(camera.IsBusy);
            Assert.True(api.Handle.IsClosed);
            if (cancel) Assert.False(File.Exists(api.Path));
        }
        finally { api.Complete.TrySetResult(); if (api.Path is { } path) File.Delete(path); }
    }

    private sealed class Api : INativeScreenCaptureApi
    {
        internal TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource Complete = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal (string Camera, string Mic, int Monitor, ScreenCaptureViewport Viewport) Selection;
        internal SafeWaitHandle? Handle;
        internal string? Path;
        public int Record(string path, int duration, int monitor, double faceRatio, ScreenCaptureViewport viewport,
            string camera, string microphone, SafeWaitHandle handle, Action<CapturePreviewFrame> preview, out double aspect)
        {
            Selection = (camera, microphone, monitor, viewport); Handle = handle; Path = path;
            preview(new(2, 2, [0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255]));
            Entered.TrySetResult(); Complete.Task.GetAwaiter().GetResult();
            File.WriteAllBytes(path, [1, 2]); aspect = 16d / 9;
            return 0;
        }
        public int Record(string path, int duration, int monitor, double ratio, ScreenCaptureViewport viewport,
            SafeWaitHandle handle, out double aspect) => throw new Exception("unselected recording");
        public int Preview(string path, int monitor, ScreenCaptureViewport viewport, SafeWaitHandle handle, out double aspect)
            => throw new NotSupportedException();
        public int SelfTest() => throw new NotSupportedException();
    }
}
