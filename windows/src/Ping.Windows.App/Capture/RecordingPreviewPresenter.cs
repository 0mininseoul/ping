#if WINDOWS
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;

namespace Ping.Windows.App.Capture;

internal sealed class RecordingPreviewPresenter
{
    private readonly Image image;
    private readonly Action frameShown;
    private readonly DispatcherQueueTimer timer;
    private CapturePreviewFrame? latest;
    private SoftwareBitmapSource? source;
    private Task rendering = Task.CompletedTask;
    private int generation;
    private bool active;

    internal RecordingPreviewPresenter(Image image, Action frameShown)
    {
        this.image = image; this.frameShown = frameShown;
        timer = image.DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(33);
        timer.Tick += Tick;
    }

    internal Action<CapturePreviewFrame> Start()
    {
        var epoch = Interlocked.Increment(ref generation);
        active = true; source = new(); timer.Start();
        return frame =>
        {
            if (epoch != Volatile.Read(ref generation)) return;
            Interlocked.Exchange(ref latest, frame);
            if (epoch != Volatile.Read(ref generation)) Interlocked.Exchange(ref latest, null);
        };
    }

    private void Tick(DispatcherQueueTimer sender, object args)
    {
        if (!active || !rendering.IsCompleted) return;
        var frame = Interlocked.Exchange(ref latest, null);
        if (frame is not null) rendering = RenderAsync(frame, generation);
    }

    private async Task RenderAsync(CapturePreviewFrame frame, int epoch)
    {
        try
        {
            using var bitmap = new SoftwareBitmap(BitmapPixelFormat.Bgra8, frame.Width, frame.Height, BitmapAlphaMode.Premultiplied);
            bitmap.CopyFromBuffer(frame.Pixels.ToArray().AsBuffer());
            var target = source!;
            await target.SetBitmapAsync(bitmap);
            if (!active || generation != epoch) return;
            image.Source = target; image.Visibility = Visibility.Visible;
            frameShown();
        }
        catch (Exception) { System.Diagnostics.Debug.WriteLine("Ping recording preview could not display this frame."); }
    }

    internal async Task StopAsync()
    {
        active = false; var epoch = Interlocked.Increment(ref generation);
        timer.Stop(); Interlocked.Exchange(ref latest, null);
        await rendering;
        if (generation != epoch) return;
        image.Visibility = Visibility.Collapsed; image.Source = null; source = null;
    }
}
#endif
