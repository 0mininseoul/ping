#if PING_UI_SMOKE
using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;
using Ping.Windows.App.Playback;
using Ping.Windows.Core.Models;
using global::Windows.Media.Editing;
using global::Windows.Media.MediaProperties;
using global::Windows.Media.Transcoding;
using global::Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

internal static class PlaybackSmoke
{
    public static async Task RunAsync(Window owner, string output, Action<bool, string> check,
        Func<FrameworkElement, string, Task> render)
    {
        var folder = await StorageFolder.GetFolderFromPathAsync(output);
        var clip = await folder.CreateFileAsync("synthetic-playback.mp4", CreationCollisionOption.FailIfExists);
        var composition = new MediaComposition();
        composition.Clips.Add(MediaClip.CreateFromColor(Colors.CornflowerBlue, TimeSpan.FromSeconds(1)));
        var transcode = await composition.RenderToFileAsync(clip, MediaTrimmingPreference.Precise, MediaEncodingProfile.CreateMp4(VideoEncodingQuality.Wvga));
        check(transcode == TranscodeFailureReason.None, "synthetic MP4 generated without camera or backend");
        var seen = 0;
        var ended = 0;
        var vm = new PlaybackViewModel(Message(), clip.Path, _ => { seen++; return Task.CompletedTask; });
        vm.PlaybackEnded += (_, _) => ended++;
        var face = new PlaybackWindow(vm, owner);
        var faceClosed = false;
        face.Closed += (_, _) => faceClosed = true;
        try
        {
            face.Activate();
            await Task.Delay(200);
            var root = (FrameworkElement)face.Content;
            var dpi = GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(face)) / 96d;
            check(Math.Abs(root.ActualWidth - 200) < 1 && Math.Abs(root.ActualHeight - 200) < 1, "real face player uses200-DIP square at current display scale");
            GetClientRect(WinRT.Interop.WindowNative.GetWindowHandle(face), out var client);
            check(Math.Abs((client.Right - client.Left) / dpi - 200) < 2,
                $"real native player client size matches DIP scale (outer={face.AppWindow.Size.Width}, client={client.Right - client.Left}, scale={dpi})");
            var origin = new NativePoint();
            ClientToScreen(WinRT.Interop.WindowNative.GetWindowHandle(face), ref origin);
            check(Math.Abs(origin.X / dpi - face.Placement.X) < 1 && Math.Abs(origin.Y / dpi - face.Placement.Y) < 1,
                "real native client origin matches requested sender placement");
            check(Math.Abs(face.Placement.Y + face.Placement.Height / 2 - (face.WorkAreaDips.Y + face.WorkAreaDips.Height * .2)) < 1,
                "real Mac upper-screen wire position maps to Windows upper screen");
            check(face.AppWindow.Presenter is OverlappedPresenter { HasBorder: false, HasTitleBar: false, IsAlwaysOnTop: true }, "real player is borderless and always on top");
            var surface = (FrameworkElement)root.FindName("PlayerSurface");
            check(ElementCompositionPreview.GetElementVisual(surface).Clip is not null, "real media surface has circular composition clip");
            var region = CreateRectRgn(0, 0, 0, 0);
            try
            {
                check(GetWindowRgn(WinRT.Interop.WindowNative.GetWindowHandle(face), region) != 0
                    && !PtInRegion(region, 0, 0) && PtInRegion(region, face.AppWindow.Size.Width / 2, face.AppWindow.Size.Height / 2),
                    "real native face window excludes square corners");
            }
            finally { DeleteObject(region); }
            await render(root, "playback-face.png");
            await WaitAsync(() => ended == 1 && seen == 1);
            check(vm.IsAwaitingDismissal && !faceClosed, "actual MediaPlayer completion waits for replay or dismissal and marks seen once");
            vm.HandleEnter();
            await WaitAsync(() => ended == 2);
            check(seen == 1 && vm.IsAwaitingDismissal, "actual media replays without duplicate seen acknowledgement");
            vm.HandleEscape();
            await WaitAsync(() => faceClosed);
            check(faceClosed, "real face playback fades out and closes on dismissal");
        }
        finally { if (!faceClosed) face.Close(); }

        var screenVm = new PlaybackViewModel(Message() with { CaptureMode = CaptureMode.ScreenFace, AspectRatio = 16d / 9 }, clip.Path, _ => Task.CompletedTask);
        var screen = new PlaybackWindow(screenVm, owner, historyReplay: true);
        var screenClosed = false;
        screen.Closed += (_, _) => screenClosed = true;
        try
        {
            screen.Activate();
            await Task.Delay(200);
            var placement = screen.Placement;
            var area = screen.WorkAreaDips;
            check(placement.Width <= 600 && Math.Abs(placement.Width / placement.Height - 16d / 9) < .001,
                "real history screen player fits600-DIP target and video aspect");
            check(placement.X >= area.X + 31 && placement.Y >= area.Y + 31 && placement.Right <= area.Right - 31 && placement.Bottom <= area.Bottom - 31,
                "real screen history player preserves32-DIP display margins");
            await render((FrameworkElement)screen.Content, "playback-screen-history.png");
            await WaitAsync(() => screenVm.IsAwaitingDismissal);
            var pausedAt = DateTimeOffset.UtcNow;
            await WaitAsync(() => screenClosed, TimeSpan.FromSeconds(12));
            check(screenClosed && DateTimeOffset.UtcNow - pausedAt >= TimeSpan.FromSeconds(9),
                "real paused player waits10 seconds then fades out and releases window");
        }
        finally { if (!screenClosed) screen.Close(); }
    }

    private static async Task WaitAsync(Func<bool> condition, TimeSpan? duration = null)
    {
        using var timeout = new CancellationTokenSource(duration ?? TimeSpan.FromSeconds(8));
        while (!condition()) await Task.Delay(20, timeout.Token);
    }

    private static VideoMessage Message() => new()
    {
        Id = "owned-playback", RoomId = "fixture", SenderUid = "peer", ReceiverUid = "me", SenderNickname = "서연", VideoId = "owned",
        VideoUrl = "peer/owned.mp4", DurationMs = 1000, MirrorPosition = new(.25, .8), Status = MessageStatus.Uploaded,
        CreatedAt = DateTimeOffset.UtcNow, ExpiresAt = DateTimeOffset.UtcNow.AddDays(1)
    };

    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref NativePoint point);
    [DllImport("user32.dll")] private static extern int GetWindowRgn(IntPtr hwnd, IntPtr region);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
    [DllImport("gdi32.dll")] private static extern bool PtInRegion(IntPtr region, int x, int y);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr handle);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }
}
#endif
