#if WINDOWS
using Microsoft.UI.Xaml;

namespace Ping.Windows.App.UI;

internal static class WindowIcon
{
    internal static void Apply(Window window)
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "Ping.ico");
        if (File.Exists(path)) window.AppWindow.SetIcon(path);
    }
}
#endif
