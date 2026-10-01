#if WINDOWS
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Ping.Windows.App.UI;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Capture;

internal sealed class CaptureMirrorWindowHost : IDisposable
{
    private readonly CaptureMirrorNativeWindow native;
    private readonly FrameworkElement root;
    private readonly CaptureMode mode;
    private readonly Action<CaptureRect, CaptureMirrorDisplay, bool> moved;
    private readonly Action<double, double> sized;
    private readonly CaptureDisplayObserver observer;
    private readonly CaptureMirrorDrag drag;
    private CaptureMirrorDisplay? display;
    private XamlRoot? xamlRoot;
    private bool applying, disposed;

    internal CaptureMirrorWindowHost(Window window, FrameworkElement root, CaptureMode mode, MirrorPosition preferred,
        Action<CaptureRect, CaptureMirrorDisplay, bool> moved, Action<double, double> sized, UIElement excludedFromDrag)
    {
        this.root = root; this.mode = mode; this.moved = moved; this.sized = sized;
        native = new(window);
        Apply(preferred);
        observer = new(native.Handle, root.DispatcherQueue, Refresh);
        drag = new(root, native, Refresh, excludedFromDrag, mode == CaptureMode.ScreenFace);
        native.Window.Changed += HandleChanged;
        root.Loaded += HandleLoaded;
    }

    private void Apply(MirrorPosition preferred, bool clamp = true)
    {
        if (disposed || applying) return;
        applying = true;
        try
        {
            display = native.ReadDisplay();
            var geometry = CaptureMirrorLayout.Create(mode, display.Display, display.WorkArea, display.Scale, preferred);
            var bounds = geometry.PixelBounds;
            if (!clamp)
            {
                var current = native.ReadClient();
                bounds = bounds with { X = Math.Round(current.X + current.Width / 2 - bounds.Width / 2),
                    Y = Math.Round(current.Y + current.Height / 2 - bounds.Height / 2) };
            }
            root.Width = geometry.WidthDip; root.Height = geometry.HeightDip;
            sized(geometry.WidthDip, geometry.HeightDip);
            RoundedCompositionClip.Apply(root, geometry.WidthDip, geometry.HeightDip, mode == CaptureMode.FaceOnly ? geometry.WidthDip / 2 : 16);
            native.PlaceClient(bounds);
            native.ApplyRegion(mode, display.Scale);
            moved(native.ReadClient(), display, !(drag?.IsDragging ?? false));
        }
        finally { applying = false; }
    }

    internal CaptureMirrorDisplay ReadDisplay() => native.ReadDisplay();
    internal CaptureRect ReadClient() => native.ReadClient();

    internal void Refresh()
    {
        if (disposed || applying) return;
        var snapshot = native.ReadDisplay();
        var client = native.ReadClient();
        if (display != snapshot || !(drag?.IsDragging ?? false))
            Apply(CaptureMirrorLayout.SenderPosition(client, snapshot.WorkArea), !(drag?.IsDragging ?? false));
        else moved(client, snapshot, !drag.IsDragging);
    }

    private void HandleChanged(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (disposed || applying || !args.DidPositionChange && !args.DidSizeChange) return;
        var snapshot = native.ReadDisplay();
        if (snapshot != display || args.DidSizeChange) Refresh();
        else moved(native.ReadClient(), snapshot, !drag.IsDragging);
    }
    private void HandleLoaded(object sender, RoutedEventArgs args)
    {
        if (disposed) return;
        xamlRoot = root.XamlRoot;
        if (xamlRoot is not null) xamlRoot.Changed += HandleXamlRootChanged;
        Refresh();
    }
    private void HandleXamlRootChanged(XamlRoot sender, XamlRootChangedEventArgs args)
    {
        if (!disposed && !applying && native.ReadDisplay() != display) Refresh();
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        native.Window.Changed -= HandleChanged;
        root.Loaded -= HandleLoaded;
        if (xamlRoot is not null) xamlRoot.Changed -= HandleXamlRootChanged;
        observer.Dispose(); drag.Dispose();
    }
}
#endif
