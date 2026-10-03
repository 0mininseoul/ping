#if PING_UI_SMOKE
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Ping.Windows.App.Diagnostics;

internal static class TypographySmoke
{
    internal static void Verify(FrameworkElement root, Action<bool, string> check)
    {
        var nodes = Nodes(root).ToArray();
        var input = nodes.OfType<TextBox>().Single(t => t.Name == "ChatBox");
        check(input.FontFamily.Source.Contains("PretendardVariable.ttf#Pretendard Variable") && input.FontSize == 14,
            "native compose input uses packaged Pretendard at readable 14 DIP");
        check(nodes.OfType<TextBlock>().Where(t => t.Text is "내 룸" or "기본 전송 대상")
                .All(t => t.FontFamily.Source.Contains("PretendardVariable.ttf")),
            "sidebar labels and templated text share the packaged typeface");
        check(nodes.OfType<FontIcon>().All(i => !i.FontFamily.Source.Contains("Pretendard")),
            "changing text typography preserves the Windows icon glyph font");
        var family = (FontFamily)Application.Current.Resources["PingFontFamily"];
        var actual = new TextBlock { Text = "Hamburgefontsiv 0123456789", FontFamily = family, FontSize = 32 };
        var fallback = new TextBlock { Text = actual.Text, FontFamily = new("Malgun Gothic"), FontSize = 32 };
        actual.Measure(new(double.PositiveInfinity, double.PositiveInfinity));
        fallback.Measure(new(double.PositiveInfinity, double.PositiveInfinity));
        check(Math.Abs(actual.DesiredSize.Width - fallback.DesiredSize.Width) > 2,
            "bundled font resolves to distinct glyph metrics rather than silently using Korean system fallback");
    }

    private static IEnumerable<DependencyObject> Nodes(DependencyObject root)
    {
        yield return root;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var node in Nodes(VisualTreeHelper.GetChild(root, i))) yield return node;
    }
}
#endif
