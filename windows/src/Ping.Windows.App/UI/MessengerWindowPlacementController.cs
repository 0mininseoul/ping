using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;

namespace Ping.Windows.App.UI;

internal sealed class MessengerWindowPlacementController : IDisposable
{
    private readonly AppWindow window;
    private readonly nint handle;
    private readonly MessengerWindowPlacementStore? store;
    private readonly DispatcherQueueTimer saveTimer;
    private MessengerPlacement? lastNormal;
    private bool updating;
    private bool disposed;

    internal MessengerWindowPlacementController(AppWindow window, nint handle, MessengerWindowPlacementStore? store)
    {
        this.window = window; this.handle = handle; this.store = store;
        saveTimer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        saveTimer.IsRepeating = false;
        saveTimer.Interval = TimeSpan.FromMilliseconds(300);
        saveTimer.Tick += (_, _) => Flush();
    }

    internal bool Restore()
    {
        var saved = store?.Load();
        var area = CurrentArea();
        if (saved is not null)
        {
            var nativeDisplays = DisplayArea.FindAll();
            var displays = new List<DisplayArea>(nativeDisplays.Count);
            // This runtime's vector view supports indexing but not the projected enumerator.
            for (var index = 0; index < nativeDisplays.Count; index++) displays.Add(nativeDisplays[index]);
            var fallback = displays.FirstOrDefault(display => display.IsPrimary) ?? area;
            var device = MessengerPlacementGeometry.SelectDevice(saved, displays.Select(DeviceName).ToArray(), DeviceName(fallback));
            area = displays.FirstOrDefault(display => DeviceName(display) == device) ?? fallback;
            // Move before reading window DPI so the saved logical size uses the target monitor.
            window.Move(new(area.WorkArea.X + 8, area.WorkArea.Y + 8));
        }
        var scale = Scale;
        UpdateMinimum(area, scale);
        var bounds = MessengerPlacementGeometry.Restore(saved, Work(area), scale);
        window.MoveAndResize(new(bounds.X, bounds.Y, bounds.Width, bounds.Height));
        CaptureNormal();
        window.Changed += Changed;
        return saved is not null;
    }

    internal void Flush()
    {
        if (disposed) return;
        saveTimer.Stop();
        CaptureNormal();
        if (lastNormal is not null) store?.Save(lastNormal);
    }

    private void Changed(AppWindow sender, AppWindowChangedEventArgs args)
    {
        if (disposed || updating || (!args.DidPositionChange && !args.DidSizeChange)) return;
        updating = true;
        try
        {
            UpdateMinimum(CurrentArea(), Scale);
            if (CaptureNormal() && store is not null) { saveTimer.Stop(); saveTimer.Start(); }
        }
        finally { updating = false; }
    }

    private bool CaptureNormal()
    {
        if (window.Presenter is not OverlappedPresenter { State: OverlappedPresenterState.Restored }
            || window.Size.Width <= 0 || window.Size.Height <= 0) return false;
        var area = CurrentArea();
        lastNormal = MessengerPlacementGeometry.Capture(DeviceName(area),
            new(window.Position.X, window.Position.Y, window.Size.Width, window.Size.Height), Work(area), Scale);
        return true;
    }

    private void UpdateMinimum(DisplayArea area, double scale)
    {
        if (window.Presenter is not OverlappedPresenter presenter) return;
        var width = Math.Max(1, Math.Min(area.WorkArea.Width, (int)Math.Round(560 * scale)));
        var height = Math.Max(1, Math.Min(area.WorkArea.Height, (int)Math.Round(540 * scale)));
        if (presenter.PreferredMinimumWidth != width) presenter.PreferredMinimumWidth = width;
        if (presenter.PreferredMinimumHeight != height) presenter.PreferredMinimumHeight = height;
    }

    private DisplayArea CurrentArea() => DisplayArea.GetFromWindowId(window.Id, DisplayAreaFallback.Nearest);
    private double Scale { get { var dpi = GetDpiForWindow(handle); return dpi == 0 ? 1 : dpi / 96d; } }
    private static MessengerWorkArea Work(DisplayArea area) => new(area.WorkArea.X, area.WorkArea.Y, area.WorkArea.Width, area.WorkArea.Height);

    internal static string DeviceName(DisplayArea area)
    {
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(Win32Interop.GetMonitorFromDisplayId(area.DisplayId), ref info)) return string.Empty;
        return info.DeviceName;
    }

    public void Dispose()
    {
        if (disposed) return;
        Flush(); disposed = true;
        window.Changed -= Changed;
        saveTimer.Stop();
    }

    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct MonitorInfo
    {
        public int Size; public Rect Bounds, WorkArea; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
    }
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(nint window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
}
