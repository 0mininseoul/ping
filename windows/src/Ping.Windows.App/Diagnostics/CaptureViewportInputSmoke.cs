#if PING_UI_SMOKE
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Ping.Windows.App.Capture;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Models;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.System;

namespace Ping.Windows.App.Diagnostics;

internal static class CaptureViewportInputSmoke
{
    internal static async Task RunAsync(string output, Action<bool, string> check, Func<FrameworkElement, string, Task> render)
    {
        var rooms = new[] { Room("one", "친구 1"), Room("two", "친구 2") };
        var camera = new CameraOwnership();
        var engine = new SyntheticScreen(output);
        var model = new ScreenFaceMirrorViewModel(new(rooms, "me", "나", "친구", false, false), engine, (_, _) => Task.CompletedTask);
        var window = new ScreenFaceMirrorWindow(model, camera.TryAcquire(CameraPurpose.Manual)!, _ => new NoPreview());
        var input = window.ViewportInput;
        try
        {
            window.Activate(); await Task.Delay(80);
            var root = (FrameworkElement)window.Content;
            var inactiveMonitor = new CaptureWheelMonitor(root.DispatcherQueue, (_, _, _) => check(false, "inactive wheel monitor must not deliver user input"));
            try { await inactiveMonitor.Ready.WaitAsync(TimeSpan.FromSeconds(3)); }
            finally { await inactiveMonitor.StopAsync(); }
            check(true, "native wheel hook registers and owning message-loop thread exits after unhook without reading input packets");
            var display = input.DisplayBounds;
            var x = display.X + display.Width * .75; var y = display.Y + display.Height / 2;
            check(!input.Wheel(120, x, y, false) && model.Viewport.Zoom == 1, "ordinary wheel preserves viewport");
            check(input.Wheel(60, x, y, true) && model.Viewport.Zoom == 1.125, "Alt wheel keeps fractional wheel deltas");
            input.Wheel(420, x, y, true);
            check(model.Viewport.Zoom == 2 && Math.Abs(model.Viewport.CenterX - .75) < .001,
                "Alt wheel zooms toward full-display pointer position");
            await model.LoadPreviewAsync();
            check(engine.LastPreview == model.Viewport, "actual mirror preview engine receives selected viewport");
            await Task.Delay(100);
            await render(root, "capture-viewport-right.png");
            var bitmap = new RenderTargetBitmap(); await bitmap.RenderAsync(root);
            var pixels = (await bitmap.GetPixelsAsync()).ToArray();
            var center = (bitmap.PixelHeight / 2 * bitmap.PixelWidth + bitmap.PixelWidth / 2) * 4;
            check(pixels[center] > 180 && pixels[center + 2] < 60, "actual mirror displays cropped blue half of owned synthetic image");
            check(((TextBlock)root.FindName("ViewportGuideLabel")).Text.Contains("2×"), "actual mirror shows zoom value and short Korean guide");
            input.Pinch(1.5, display.X + display.Width / 2, y, true);
            check(model.Viewport.Zoom == 3, "supported pinch scale changes zoom through same viewport controller");
            input.TrackPointer(display.X + display.Width * .25, y, true);
            check(Math.Abs(model.Viewport.CenterX - .25) < .001, "Alt pointer tracking moves crop center across full capture display");
            model.SelectTargetAtIndex(0);
            check(window.HandleTargetOrViewportKey(VirtualKey.Number0, true) && model.Viewport == new ScreenCaptureViewport() && !model.IsAllTargetsSelected,
                "Alt0 resets viewport before recipient shortcut handling");
            check(window.HandleTargetOrViewportKey(VirtualKey.Number0, false) && model.IsAllTargetsSelected,
                "plain0 retains all-recipient shortcut");
            input.Wheel(480, x, y, true);
            var frozen = model.Viewport;
            await window.HandleEnterAsync();
            model.SelectTargetAtIndex(0);
            check(!input.Wheel(120, x, y, true) && window.HandleTargetOrViewportKey(VirtualKey.Number0, true)
                && model.Viewport == frozen && !model.IsAllTargetsSelected,
                "review rejects viewport edits and consumes Alt0 without changing recipient");
        }
        finally { window.Close(); await window.CameraShutdown; }
        check(!camera.IsBusy && !input.Wheel(120, 0, 0, true), "closed mirror disposes input adapter and releases camera lease");
    }

    private static Room Room(string id, string name) => new(id, name, name, "me", ["me", "peer"], new Dictionary<string, string>(), RoomStatus.Open);
    private sealed class NoPreview : IFacePreviewSession
    {
        public Task StartPreviewAsync(MediaPlayerElement element, CancellationToken token = default) => Task.CompletedTask;
        public Task StopPreviewAsync(MediaPlayerElement element) => Task.CompletedTask;
    }
    private sealed class SyntheticScreen(string output) : IScreenFaceCaptureEngine
    {
        internal ScreenCaptureViewport? LastPreview;
        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitor, ScreenCaptureViewport viewport, CancellationToken token)
        {
            LastPreview = viewport;
            var path = Path.Combine(output, $"owned-viewport-{Guid.NewGuid():N}.bmp");
            var crop = viewport.CropRect(new(0, 0, 160, 90));
            using var writer = new BinaryWriter(File.Create(path));
            writer.Write((ushort)0x4d42); writer.Write(54 + 160 * 90 * 4); writer.Write(0); writer.Write(54);
            writer.Write(40); writer.Write(160); writer.Write(-90); writer.Write((ushort)1); writer.Write((ushort)32);
            writer.Write(0); writer.Write(160 * 90 * 4); writer.Write(0); writer.Write(0); writer.Write(0); writer.Write(0);
            for (var y = 0; y < 90; y++) for (var x = 0; x < 160; x++)
            {
                var blue = crop.X + (x + .5) / 160 * crop.Width >= 80;
                writer.Write(blue ? (byte)255 : (byte)0); writer.Write((byte)0); writer.Write(blue ? (byte)0 : (byte)255); writer.Write((byte)255);
            }
            return Task.FromResult(new ScreenFacePreviewResult(path, 16d / 9));
        }
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, ScreenCaptureViewport viewport, CancellationToken token)
        {
            var path = Path.Combine(output, $"owned-viewport-review-{Guid.NewGuid():N}.mp4");
            File.Copy(Path.Combine(output, "synthetic-playback.mp4"), path);
            return Task.FromResult(new ScreenFaceCaptureResult(path, 16d / 9));
        }
        public Task<ScreenFaceCaptureResult> RecordAsync(TimeSpan duration, int monitor, CancellationToken token) => throw new NotSupportedException();
        public Task<ScreenFacePreviewResult> CapturePreviewAsync(int monitor, CancellationToken token) => throw new NotSupportedException();
        public Task<ScreenCaptureSelfTestResult> SelfTestAsync() => throw new NotSupportedException();
    }
}
#endif
