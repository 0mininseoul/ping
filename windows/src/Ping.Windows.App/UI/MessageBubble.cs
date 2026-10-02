using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Ping.Windows.App.UI;

public sealed class MessageBubble : ContentControl
{
    public static readonly DependencyProperty IsMineProperty = DependencyProperty.Register(
        nameof(IsMine), typeof(bool), typeof(MessageBubble), new PropertyMetadata(false, Refresh));
    public static readonly DependencyProperty SentFillProperty = BrushProperty(nameof(SentFill));
    public static readonly DependencyProperty ReceivedFillProperty = BrushProperty(nameof(ReceivedFill));
    public static readonly DependencyProperty SentTextProperty = BrushProperty(nameof(SentText));
    public static readonly DependencyProperty ReceivedTextProperty = BrushProperty(nameof(ReceivedText));

    public bool IsMine { get => (bool)GetValue(IsMineProperty); set => SetValue(IsMineProperty, value); }
    public Brush? SentFill { get => (Brush?)GetValue(SentFillProperty); set => SetValue(SentFillProperty, value); }
    public Brush? ReceivedFill { get => (Brush?)GetValue(ReceivedFillProperty); set => SetValue(ReceivedFillProperty, value); }
    public Brush? SentText { get => (Brush?)GetValue(SentTextProperty); set => SetValue(SentTextProperty, value); }
    public Brush? ReceivedText { get => (Brush?)GetValue(ReceivedTextProperty); set => SetValue(ReceivedTextProperty, value); }

    private static DependencyProperty BrushProperty(string name) => DependencyProperty.Register(
        name, typeof(Brush), typeof(MessageBubble), new PropertyMetadata(null, Refresh));
    private static void Refresh(DependencyObject sender, DependencyPropertyChangedEventArgs args)
    {
        var bubble = (MessageBubble)sender;
        bubble.Background = bubble.IsMine ? bubble.SentFill : bubble.ReceivedFill;
        bubble.Foreground = bubble.IsMine ? bubble.SentText : bubble.ReceivedText;
    }
}
