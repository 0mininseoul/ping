using Microsoft.Win32.SafeHandles;
using Ping.Windows.App.Capture;
using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class NativeCaptureViewportTests
{
    [Fact]
    public async Task SelectedCameraPassesExactIdentityToNativeApi()
    {
        var api = new Api();
        var id = @"\\?\fixture#camera#{opaque-id}";
        var result = await new NativeCaptureEngine(api).RecordAsync(TimeSpan.FromSeconds(3), 0, new(), id, default);
        try { Assert.Equal(id, api.SelectedCamera); Assert.True(File.Exists(result.FilePath)); }
        finally { File.Delete(result.FilePath); }
    }

    [Fact]
    public async Task UnsupportedSelectedCameraApiDoesNotFallBackToV2()
    {
        var api = new Api { RejectSelectedCamera = true };
        await Assert.ThrowsAsync<NotSupportedException>(() => new NativeCaptureEngine(api)
            .RecordAsync(TimeSpan.FromSeconds(3), 0, new(), "selected", default));
        Assert.Null(api.Handle);
        Assert.False(File.Exists(api.Path));
    }
    [Fact]
    public async Task RecordingForwardsImmutableViewportAndNativeParameters()
    {
        var api = new Api();
        var viewport = new ScreenCaptureViewport(3, .2, .7);
        var result = await new NativeCaptureEngine(api).RecordAsync(TimeSpan.FromSeconds(3), 2, viewport, default);
        try
        {
            Assert.Same(viewport, api.Viewport);
            Assert.Equal(3000, api.Duration);
            Assert.Equal(2, api.Monitor);
            Assert.Equal(.32, api.FaceRatio);
            Assert.Equal(16d / 9, result.AspectRatio);
            Assert.True(File.Exists(result.FilePath));
            Assert.True(api.Handle!.IsClosed);
        }
        finally { File.Delete(result.FilePath); }
    }

    [Fact]
    public async Task PreviewForwardsTheSameCropSnapshot()
    {
        var api = new Api();
        var viewport = new ScreenCaptureViewport(2, .4, .6);
        var result = await new NativeCaptureEngine(api).CapturePreviewAsync(1, viewport, default);
        try { Assert.Same(viewport, api.Viewport); Assert.EndsWith(".bmp", result.FilePath); }
        finally { File.Delete(result.FilePath); }
    }

    [Fact]
    public async Task CancellationSignalsNativeEventAndWaitsForUnderlyingCleanup()
    {
        var api = new Api { WaitForCancellation = true };
        using var cancellation = new CancellationTokenSource();
        var operation = new NativeCaptureEngine(api).RecordAsync(TimeSpan.FromSeconds(3), 0, new(), cancellation.Token);
        await api.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        cancellation.Cancel();
        try
        {
            await api.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Assert.False(operation.IsCompleted);
            Assert.False(api.Handle!.IsClosed);
        }
        finally { api.Finish.Set(); }
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => operation);
        Assert.True(api.Handle!.IsClosed);
        Assert.False(File.Exists(api.Path));
    }

    [Fact]
    public async Task NativeExceptionDeletesPartialOutput()
    {
        var api = new Api { Fail = true };
        await Assert.ThrowsAsync<IOException>(() => new NativeCaptureEngine(api).RecordAsync(TimeSpan.FromSeconds(3), 0, new(), default));
        Assert.False(File.Exists(api.Path));
        Assert.True(api.Handle!.IsClosed);
    }

    [Fact]
    public async Task OwnedViewportRecordingPreservesLeaseUntilNativeCleanup()
    {
        var camera = new CameraOwnership();
        var api = new Api { WaitForCancellation = true };
        using var cancellation = new CancellationTokenSource();
        var viewport = new ScreenCaptureViewport(2);
        var owned = new OwnedScreenFaceCaptureEngine(camera, new NativeCaptureEngine(api), selectCamera: _ => Task.FromResult("fixture-camera"));
        var operation = owned.RecordAsync(TimeSpan.FromSeconds(3), 0, viewport, cancellation.Token);
        await api.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        cancellation.Cancel();
        try
        {
            await api.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Assert.True(camera.IsBusy);
            Assert.Same(viewport, api.Viewport);
        }
        finally { api.Finish.Set(); }
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => operation);
        Assert.False(camera.IsBusy);
    }

    private sealed class Api : INativeScreenCaptureApi
    {
        public ScreenCaptureViewport? Viewport;
        public string? SelectedCamera;
        public bool RejectSelectedCamera;
        public SafeWaitHandle? Handle;
        public string Path = "";
        public int Duration, Monitor;
        public double FaceRatio;
        public bool WaitForCancellation, Fail;
        public TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource Cancelled = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public ManualResetEventSlim Finish = new();
        public int Record(string path, int duration, int monitor, double faceRatio, ScreenCaptureViewport viewport,
            SafeWaitHandle cancellationEvent, out double aspect)
        {
            Duration = duration; FaceRatio = faceRatio;
            return Execute(path, monitor, viewport, cancellationEvent, out aspect);
        }
        public int Record(string path, int duration, int monitor, double faceRatio, ScreenCaptureViewport viewport,
            string cameraDeviceId, SafeWaitHandle cancellationEvent, out double aspect)
        {
            SelectedCamera = cameraDeviceId;
            if (RejectSelectedCamera) throw new NotSupportedException("fixture V3 unavailable");
            return Record(path, duration, monitor, faceRatio, viewport, cancellationEvent, out aspect);
        }
        public int Preview(string path, int monitor, ScreenCaptureViewport viewport, SafeWaitHandle cancellationEvent, out double aspect)
            => Execute(path, monitor, viewport, cancellationEvent, out aspect);
        public int SelfTest() => 0;
        private int Execute(string path, int monitor, ScreenCaptureViewport viewport, SafeWaitHandle handle, out double aspect)
        {
            Path = path; Monitor = monitor; Viewport = viewport; Handle = handle; aspect = 16d / 9;
            Started.TrySetResult();
            if (WaitForCancellation)
            {
                using var signal = new EventWaitHandle(false, EventResetMode.ManualReset);
                signal.SafeWaitHandle = new SafeWaitHandle(handle.DangerousGetHandle(), ownsHandle: false);
                if (!signal.WaitOne(TimeSpan.FromSeconds(3))) throw new TimeoutException("Native cancellation was not signalled.");
                Cancelled.TrySetResult();
                if (!Finish.Wait(TimeSpan.FromSeconds(3))) throw new TimeoutException("Fixture cleanup was not released.");
            }
            File.WriteAllBytes(path, [1, 2, 3]);
            if (Fail) throw new IOException("Native failure after partial output.");
            return 0;
        }
    }
}
