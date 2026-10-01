#if WINDOWS
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

internal sealed class CaptureViewportInput
{
    private readonly ScreenFaceMirrorViewModel model;
    private readonly FrameworkElement root;
    private readonly CaptureMirrorWindowHost host;
    private readonly DispatcherQueueTimer timer;
    private readonly CaptureWheelMonitor? wheelMonitor;
    private bool disposed, globalWheelReady;
    private Task? stopTask;
    internal CaptureRect DisplayBounds => host.ReadDisplay().Display;
    internal static bool AltPressed => GetAsyncKeyState(0x12) < 0;

    internal CaptureViewportInput(ScreenFaceMirrorViewModel model, FrameworkElement root, CaptureMirrorWindowHost host)
    {
        this.model = model; this.root = root; this.host = host;
        root.ManipulationMode = ManipulationModes.Scale;
        root.ManipulationDelta += HandleManipulation;
        root.PointerWheelChanged += HandleLocalWheel;
        model.PropertyChanged += HandleModelChanged;
        timer = root.DispatcherQueue.CreateTimer(); timer.Interval = TimeSpan.FromMilliseconds(33);
        timer.Tick += HandleTick;
        wheelMonitor = null;
#if !PING_UI_SMOKE
        wheelMonitor = new(root.DispatcherQueue, (delta, x, y) => Wheel(delta, x, y, true));
        globalWheelReady = true;
        RefreshState();
        timer.Start();
        _ = ObserveWheelStartupAsync();
#endif
    }

    private async Task ObserveWheelStartupAsync()
    {
        try { await wheelMonitor!.Ready; if (!disposed) globalWheelReady = true; }
        catch (Exception)
        {
            if (!disposed) { globalWheelReady = false; model.UseLocalViewportWheel(); }
        }
    }

    internal bool Wheel(double delta, double x, double y, bool alt)
    {
        var adjustment = ScreenCaptureViewport.WheelAdjustment(delta);
        if (!Editable(alt) || adjustment == 0 || !CaptureWheelMonitor.Contains(DisplayBounds, x, y)) return false;
        model.UpdateViewport(model.Viewport.AdjustZoom(adjustment).MoveCenterTo(x, y, DisplayBounds));
        return true;
    }
    internal bool Pinch(double scale, double x, double y, bool alt)
    {
        if (!Editable(alt) || !double.IsFinite(scale) || scale <= 0 || scale == 1 || !CaptureWheelMonitor.Contains(DisplayBounds, x, y)) return false;
        model.UpdateViewport(model.Viewport.AdjustZoom(model.Viewport.Zoom * (scale - 1)).MoveCenterTo(x, y, DisplayBounds));
        return true;
    }
    internal bool TrackPointer(double x, double y, bool alt)
    {
        if (!Editable(alt)) return false;
        return model.UpdateViewport(model.Viewport.MoveCenterTo(x, y, DisplayBounds));
    }
    internal bool Reset(bool alt)
    {
        if (!alt || disposed) return false;
        if (model.CanEditViewport) model.UpdateViewport(new());
        return true;
    }
    private bool Editable(bool alt) => !disposed && alt && model.CanEditViewport;

    private void HandleLocalWheel(object sender, PointerRoutedEventArgs args)
    {
        if (!Editable(AltPressed)) return;
        if (!globalWheelReady)
        {
            var point = CaptureMirrorNativeWindow.Cursor();
            Wheel(args.GetCurrentPoint(root).Properties.MouseWheelDelta, point.X, point.Y, true);
        }
        args.Handled = true;
    }
    private void HandleManipulation(object sender, ManipulationDeltaRoutedEventArgs args)
    {
        if (disposed) return;
        var display = host.ReadDisplay(); var client = host.ReadClient();
        if (Pinch(args.Delta.Scale, client.X + args.Position.X * display.Scale, client.Y + args.Position.Y * display.Scale, AltPressed)) args.Handled = true;
    }
    private void HandleTick(DispatcherQueueTimer sender, object args)
    {
        if (disposed) return;
        RefreshState();
        if (model.CanEditViewport && AltPressed)
        {
            var point = CaptureMirrorNativeWindow.Cursor();
            TrackPointer(point.X, point.Y, true);
        }
    }
    private void HandleModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName is nameof(ScreenFaceMirrorViewModel.CanEditViewport) or nameof(ScreenFaceMirrorViewModel.MonitorIndex)) RefreshState();
    }
    private void RefreshState()
    {
        if (!disposed) wheelMonitor?.SetDisplay(model.CanEditViewport ? DisplayBounds : null);
    }
    internal Task StopAsync() => stopTask ??= StopCoreAsync();
    private async Task StopCoreAsync()
    {
        disposed = true; timer.Stop(); timer.Tick -= HandleTick;
        root.ManipulationDelta -= HandleManipulation; root.PointerWheelChanged -= HandleLocalWheel;
        model.PropertyChanged -= HandleModelChanged;
        root.ManipulationMode = ManipulationModes.System;
        if (wheelMonitor is not null) await wheelMonitor.StopAsync();
    }
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
}
#endif
