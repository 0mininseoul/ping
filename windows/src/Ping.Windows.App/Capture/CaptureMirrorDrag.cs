#if WINDOWS
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

internal sealed class CaptureMirrorDrag : IDisposable
{
    private readonly FrameworkElement root;
    private readonly CaptureMirrorNativeWindow native;
    private readonly Action finished;
    private readonly UIElement excluded;
    private CaptureRect origin;
    private (double X, double Y) cursor;
    private Pointer? pointer;
    internal bool IsDragging => pointer is not null;
    internal CaptureMirrorDrag(FrameworkElement root, CaptureMirrorNativeWindow native, Action finished, UIElement excluded)
    {
        this.root = root; this.native = native; this.finished = finished; this.excluded = excluded;
        root.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler(Pressed), true);
        root.PointerMoved += Moved;
        root.PointerReleased += Released;
        root.PointerCaptureLost += Released;
    }
    private void Pressed(object sender, PointerRoutedEventArgs args)
    {
        if (IsDragging || args.Pointer.PointerDeviceType != PointerDeviceType.Mouse
            || !args.GetCurrentPoint(root).Properties.IsLeftButtonPressed || IsExcluded(args.OriginalSource as DependencyObject)) return;
        origin = native.ReadClient(); cursor = CaptureMirrorNativeWindow.Cursor();
        if (root.CapturePointer(args.Pointer)) { pointer = args.Pointer; root.Focus(FocusState.Programmatic); }
    }
    private void Moved(object sender, PointerRoutedEventArgs args)
    {
        if (pointer?.PointerId != args.Pointer.PointerId) return;
        var current = CaptureMirrorNativeWindow.Cursor();
        native.MoveClient(origin.X + current.X - cursor.X, origin.Y + current.Y - cursor.Y);
        args.Handled = true;
    }
    private void Released(object sender, PointerRoutedEventArgs args)
    {
        if (pointer?.PointerId != args.Pointer.PointerId) return;
        var captured = pointer; pointer = null;
        root.ReleasePointerCapture(captured);
        finished();
    }
    private bool IsExcluded(DependencyObject? source)
    {
        while (source is not null)
        {
            if (source == excluded) return true;
            source = VisualTreeHelper.GetParent(source);
        }
        return false;
    }
    public void Dispose()
    {
        root.RemoveHandler(UIElement.PointerPressedEvent, new PointerEventHandler(Pressed));
        root.PointerMoved -= Moved;
        root.PointerReleased -= Released;
        root.PointerCaptureLost -= Released;
        var captured = pointer; pointer = null;
        if (captured is not null) root.ReleasePointerCapture(captured);
    }
}
#endif
