#if WINDOWS
using System.Numerics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Hosting;

namespace Ping.Windows.App.UI;

internal static class RoundedCompositionClip
{
    public static void Apply(UIElement element, double width, double height, double radius)
    {
        if (width <= 0 || height <= 0 || radius <= 0)
        {
            return;
        }

        var visual = ElementCompositionPreview.GetElementVisual(element);
        var compositor = visual.Compositor;
        var geometry = compositor.CreateRoundedRectangleGeometry();
        geometry.Size = new Vector2((float)width, (float)height);
        geometry.CornerRadius = new Vector2((float)radius, (float)radius);

        var clip = compositor.CreateGeometricClip(geometry);
        visual.Clip = clip;
    }
}
#endif
