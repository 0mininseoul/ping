#if PING_UI_SMOKE
using Microsoft.UI.Windowing;
using Ping.Windows.App.UI;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    private static async Task VerifyMessengerWindowPlacementAsync()
    {
        var store = new MessengerWindowPlacementStore(Path.Combine(OutputDirectory!, "MessengerWindowPlacement.json"));
        MainWindow? window = null;
        try
        {
            window = new(store); window.InitializeTrayWindowBehavior(); window.ShowShell();
            TestDisplayPlacement.Verify(window, Check);
            var area = DisplayArea.GetFromWindowId(window.AppWindow.Id, DisplayAreaFallback.Nearest);
            var desired = new MessengerBounds(area.WorkArea.X + 96, area.WorkArea.Y + 120, 710, 680);
            window.AppWindow.MoveAndResize(new(desired.X, desired.Y, desired.Width, desired.Height));
            await Task.Delay(400);
            Check(store.Load() is { } saved && saved.DeviceName == MessengerWindowPlacementController.DeviceName(area),
                "moving and resizing messenger persists its monitor in the owned placement file");
            window.Close();
            Check(!window.AppWindow.IsVisible && store.Load() is not null, "hiding to tray flushes the last normal messenger placement");
            window.CloseForQuit(); window = null;

            window = new(store); window.InitializeTrayWindowBehavior(); window.ShowShell();
            TestDisplayPlacement.Verify(window, Check);
            Check(Bounds(window) == desired, "new native messenger restores the same monitor position and size");
            var normal = store.Load();
            var presenter = (OverlappedPresenter)window.AppWindow.Presenter;
            presenter.Minimize(); await Task.Delay(100); window.Close();
            Check(store.Load() == normal, "minimizing does not overwrite the restored messenger bounds");
            presenter.Restore(); window.ShowShell(); await Task.Delay(100);
            presenter.Maximize(); await Task.Delay(100); window.Close();
            Check(store.Load() == normal, "maximizing does not overwrite the restored messenger bounds");
            window.CloseForQuit(); window = null;

            window = new(store); window.InitializeTrayWindowBehavior(); window.ShowShell();
            TestDisplayPlacement.Verify(window, Check);
            Check(Bounds(window) == desired && ((OverlappedPresenter)window.AppWindow.Presenter).State == OverlappedPresenterState.Restored,
                "reopening after maximized shutdown restores the usable normal rectangle");
        }
        finally { window?.CloseForQuit(); }
        static MessengerBounds Bounds(MainWindow window) => new(window.AppWindow.Position.X, window.AppWindow.Position.Y,
            window.AppWindow.Size.Width, window.AppWindow.Size.Height);
    }
}
#endif
