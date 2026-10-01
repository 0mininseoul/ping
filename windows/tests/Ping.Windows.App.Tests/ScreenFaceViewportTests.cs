using Ping.Windows.App.Capture;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class ScreenFaceViewportTests
{
    [Fact]
    public async Task PreviewAndRecordingReceiveSameImmutableSelectionThroughViewportApi()
    {
        using var engine = new Engine();
        var model = Create(engine);
        var selected = new ScreenCaptureViewport(2, .7, .3);
        Assert.True(model.UpdateViewport(selected));
        model.UpdateCaptureMonitor(2);
        await model.LoadPreviewAsync();
        Assert.Equal((2, selected), engine.Previews.Single().Selection);
        model.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(model.State) && model.State == MirrorState.Recording)
                model.UpdateCaptureMonitor(9);
        };
        await model.HandleEnterAsync();
        Assert.Equal((2, selected), engine.Recordings.Single().Selection);
        Assert.Equal(TimeSpan.FromSeconds(3), engine.Duration);
        Assert.False(model.CanEditViewport);
        Assert.False(model.UpdateViewport(new(4)));
        var path = model.ReviewVideoUri!.LocalPath;
        await model.HandleRedoAsync();
        Assert.False(File.Exists(path));
        Assert.True(model.CanEditViewport);
        Assert.Equal(selected, model.Viewport);
        Assert.True(model.UpdateViewport(new(3)));
        Assert.Single(engine.Recordings);
        model.HandleWindowClosed();
    }

    [Fact]
    public async Task RecordingFreezesViewportAndRejectsRepeatedEnterUntilActualReturn()
    {
        using var engine = new Engine { HoldRecording = true };
        var model = Create(engine);
        var selected = new ScreenCaptureViewport(2.5, .4, .6);
        model.UpdateViewport(selected);
        var recording = model.HandleEnterAsync();
        Assert.Equal(MirrorState.Recording, model.State);
        Assert.False(model.UpdateViewport(new(4)));
        await model.HandleEnterAsync();
        Assert.Single(engine.Recordings);
        engine.Recordings.Single().Complete();
        await recording;
        Assert.Equal(selected, model.Viewport);
        Assert.Equal(selected, engine.Recordings.Single().Selection.Viewport);
        model.HandleWindowClosed();
        Assert.False(model.UpdateViewport(new()));
        Assert.False(model.CanEditViewport);
    }

    [Fact]
    public async Task LatePreviewFromPreviousViewportCannotReplaceNewerFrame()
    {
        using var engine = new Engine { HoldPreview = true };
        var model = Create(engine);
        var old = model.LoadPreviewAsync();
        model.UpdateViewport(new(2));
        engine.HoldPreview = false;
        await model.LoadPreviewAsync();
        var current = model.ScreenPreviewUri;
        engine.Previews[0].Complete();
        await old;
        Assert.Equal(current, model.ScreenPreviewUri);
        Assert.True(File.Exists(current!.LocalPath));
        Assert.False(File.Exists(engine.Previews[0].Path));
        model.HandleWindowClosed();
    }

    [Fact]
    public async Task LatePreviewAfterCloseDeletesItsFileWithoutRevivingView()
    {
        using var engine = new Engine { HoldPreview = true };
        var model = Create(engine);
        var preview = model.LoadPreviewAsync();
        model.HandleWindowClosed();
        engine.Previews.Single().Complete();
        await preview;
        Assert.Null(model.ScreenPreviewUri);
        Assert.False(File.Exists(engine.Previews.Single().Path));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task PreviousSelectionPreviewIsDiscardedEvenAfterSelectionReturnsToOriginal(bool changeMonitor)
    {
        using var engine = new Engine { HoldPreview = true };
        var model = Create(engine);
        var preview = model.LoadPreviewAsync();
        if (changeMonitor) { var original = model.MonitorIndex; model.UpdateCaptureMonitor(7); model.UpdateCaptureMonitor(original); }
        else { model.UpdateViewport(new(2)); model.UpdateViewport(new()); }
        engine.Previews.Single().Complete();
        await preview;
        Assert.Null(model.ScreenPreviewUri);
        Assert.False(File.Exists(engine.Previews.Single().Path));
    }

    [Fact]
    public async Task CancellationAfterPreviewReturnsStillDeletesOutput()
    {
        using var engine = new Engine { HoldPreview = true };
        var model = Create(engine);
        using var cancellation = new CancellationTokenSource();
        var preview = model.LoadPreviewAsync(cancellation.Token);
        cancellation.Cancel();
        engine.Previews.Single().Complete();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => preview);
        Assert.Null(model.ScreenPreviewUri);
        Assert.False(File.Exists(engine.Previews.Single().Path));
    }

    [Fact]
    public async Task StalePreviewFailureDoesNotClearCurrentPreviewOrGuidance()
    {
        using var engine = new Engine { HoldPreview = true };
        var model = Create(engine);
        var old = model.LoadPreviewAsync();
        engine.HoldPreview = false;
        await model.LoadPreviewAsync();
        var current = model.ScreenPreviewUri;
        var status = model.StatusMessage;
        engine.Previews[0].Fail();
        await old;
        Assert.Equal(current, model.ScreenPreviewUri);
        Assert.Equal(status, model.StatusMessage);
        Assert.True(File.Exists(current!.LocalPath));
        model.HandleWindowClosed();
    }

    [Fact]
    public async Task UnsupportedViewportRecordingFailsWithoutFallingBackToFullDisplay()
    {
        var engine = new LegacyEngine();
        var model = Create(engine);
        model.UpdateViewport(new(2));
        await model.HandleEnterAsync();
        Assert.Equal(MirrorState.Failed, model.State);
        Assert.True(model.CanEditViewport);
        Assert.Equal(0, engine.LegacyRecordings);
        Assert.False(model.HasReviewedClip);
    }

    private static ScreenFaceMirrorViewModel Create(IScreenFaceCaptureEngine engine) => new(
        new([new Room("room", "친구", "친구", "me", ["me", "peer"], new Dictionary<string, string>(), RoomStatus.Open)],
            "me", "나", "친구", false, false), engine, (_, _) => Task.CompletedTask);

    private sealed class Request(int monitor, ScreenCaptureViewport viewport, string path)
    {
        private readonly TaskCompletionSource done = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public (int Monitor, ScreenCaptureViewport Viewport) Selection { get; } = (monitor, viewport);
        public string Path { get; } = path;
        public Task Completion => done.Task;
        public void Complete() => done.TrySetResult();
        public void Fail() { File.Delete(Path); done.TrySetException(new IOException("Owned preview failure.")); }
    }

    private sealed class Engine : IScreenFaceCaptureEngine, IDisposable
    {
        private readonly string directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"PingViewportTests-{Guid.NewGuid():N}");
        private readonly List<string> files = [];
        public bool HoldPreview, HoldRecording;
        public List<Request> Previews { get; } = [];
        public List<Request> Recordings { get; } = [];
        public TimeSpan Duration { get; private set; }
        public async Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitor, ScreenCaptureViewport viewport, CancellationToken token)
        {
            var request = CreateRequest(monitor, viewport, Previews);
            if (!HoldPreview) request.Complete();
            await request.Completion;
            return new(request.Path, 16d / 9);
        }
        public async Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, ScreenCaptureViewport viewport, CancellationToken token)
        {
            Duration = duration;
            var request = CreateRequest(monitor, viewport, Recordings);
            if (!HoldRecording) request.Complete();
            await request.Completion;
            return new(request.Path, 16d / 9);
        }
        private Request CreateRequest(int monitor, ScreenCaptureViewport viewport, List<Request> requests)
        {
            Directory.CreateDirectory(directory);
            var path = System.IO.Path.Combine(directory, $"owned-{Guid.NewGuid():N}.bin");
            File.WriteAllBytes(path, [0, 1]); files.Add(path);
            var request = new Request(monitor, viewport, path); requests.Add(request); return request;
        }
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, CancellationToken token) => throw new InvalidOperationException("Legacy API must not be used.");
        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitor, CancellationToken token) => throw new InvalidOperationException("Legacy API must not be used.");
        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => throw new NotSupportedException();
        public void Dispose() { foreach (var file in files) File.Delete(file); if (Directory.Exists(directory)) Directory.Delete(directory); }
    }
    private sealed class LegacyEngine : IScreenFaceCaptureEngine
    {
        public int LegacyRecordings;
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, CancellationToken token) { ++LegacyRecordings; throw new InvalidOperationException("Legacy fallback forbidden."); }
        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitor, CancellationToken token) => throw new NotSupportedException();
        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => throw new NotSupportedException();
    }
}
