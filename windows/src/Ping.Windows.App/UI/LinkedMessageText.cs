using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.UI;

public sealed class LinkedMessageText : UserControl
{
    private readonly TextBlock text = new() { Name = "LinkedChatBody", TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
    public static readonly DependencyProperty BodyProperty = DependencyProperty.Register(nameof(Body), typeof(string), typeof(LinkedMessageText), new PropertyMetadata("", Refresh));
    public static readonly DependencyProperty IsMineProperty = DependencyProperty.Register(nameof(IsMine), typeof(bool), typeof(LinkedMessageText), new PropertyMetadata(false, Refresh));
    public static readonly DependencyProperty SentTextProperty = BrushProperty(nameof(SentText));
    public static readonly DependencyProperty ReceivedTextProperty = BrushProperty(nameof(ReceivedText));
    public static readonly DependencyProperty ReceivedLinkProperty = BrushProperty(nameof(ReceivedLink));
    public string Body { get => (string)GetValue(BodyProperty); set => SetValue(BodyProperty, value); }
    public bool IsMine { get => (bool)GetValue(IsMineProperty); set => SetValue(IsMineProperty, value); }
    public Brush? SentText { get => (Brush?)GetValue(SentTextProperty); set => SetValue(SentTextProperty, value); }
    public Brush? ReceivedText { get => (Brush?)GetValue(ReceivedTextProperty); set => SetValue(ReceivedTextProperty, value); }
    public Brush? ReceivedLink { get => (Brush?)GetValue(ReceivedLinkProperty); set => SetValue(ReceivedLinkProperty, value); }
    public LinkedMessageText()
    {
        text.Style = (Style)Application.Current.Resources["PingBodyTextStyle"];
        Content = text;
    }
    private static DependencyProperty BrushProperty(string name) => DependencyProperty.Register(name, typeof(Brush), typeof(LinkedMessageText), new PropertyMetadata(null, Refresh));
    private static void Refresh(DependencyObject sender, DependencyPropertyChangedEventArgs args) => ((LinkedMessageText)sender).Render();
    private void Render()
    {
        text.Inlines.Clear();
        text.Foreground = IsMine ? SentText : ReceivedText;
        var body = Body ?? "";
        var offset = 0;
        foreach (var link in LinkPreviewDetector.Matches(body))
        {
            if (link.Start > offset) text.Inlines.Add(new Run { Text = body[offset..link.Start] });
            var hyperlink = new Hyperlink { NavigateUri = link.Url, Foreground = IsMine ? SentText : ReceivedLink };
            hyperlink.Inlines.Add(new Run { Text = body.Substring(link.Start, link.Length) });
            text.Inlines.Add(hyperlink);
            offset = link.Start + link.Length;
        }
        if (offset < body.Length) text.Inlines.Add(new Run { Text = body[offset..] });
    }
}
