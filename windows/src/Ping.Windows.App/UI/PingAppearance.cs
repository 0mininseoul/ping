#if WINDOWS
using Microsoft.UI.Xaml;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.UI;

internal static class PingAppearance
{
    private static readonly List<WeakReference<FrameworkElement>> roots = [];
    private static ElementTheme theme = ElementTheme.Default;

    internal static void Register(Window window)
    {
        if (window.Content is not FrameworkElement root) return;
        roots.RemoveAll(reference => !reference.TryGetTarget(out _));
        roots.Add(new(root)); root.RequestedTheme = theme;
    }

    internal static void Apply(PingAppearanceMode mode)
    {
        theme = mode switch { PingAppearanceMode.Light => ElementTheme.Light, PingAppearanceMode.Dark => ElementTheme.Dark, _ => ElementTheme.Default };
        roots.RemoveAll(reference => !reference.TryGetTarget(out _));
        foreach (var reference in roots)
            if (reference.TryGetTarget(out var root)) root.RequestedTheme = theme;
    }
}
#endif
