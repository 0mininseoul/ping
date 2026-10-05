#if PING_UI_SMOKE
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;
using Ping.Windows.App.History;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    private static async Task VerifyConversationTextAsync()
    {
        const string Body = "같이 봐 https://example.com/a 와 www.example.org.\n🙂 메일 qa@example.net";
        var rpc = new FixtureRpc { OwnChatBody = Body }; var storage = new FixtureStorage();
        var vm = new HistoryViewModel(new(rpc), new(rpc, storage), new(rpc), new(rpc), storage, () => "me", new FixtureLinks());
        var window = new MainWindow(); window.InitializeTrayWindowBehavior();
        var shell = new HistoryWindow(window, vm, (_, _) => throw new NotSupportedException(), (_, _) => Task.CompletedTask, new(rpc, storage), loadOnStart: false);
        window.AttachMessenger(shell); window.ShowShell();
        try
        {
            await shell.ReloadRoomsAsync(); await Task.Delay(100);
            Check(!Descendants(shell).OfType<TextBlock>().Any(t => t.DataContext is TimelineHistoryItem row && t.Text == row.SenderLabel && t.Visibility == Visibility.Visible),
                "one-to-one conversation hides redundant sender names for both chat and video");
            rpc.MemberCount = 3;
            await shell.ReloadRoomsAsync(); await Task.Delay(100);
            Check(Descendants(shell).OfType<TextBlock>().Count(t => t.DataContext is TimelineHistoryItem { IsMine: false } row && t.Text == row.SenderLabel && t.Visibility == Visibility.Visible) == 3,
                "group conversation shows received sender names and retains own-message alignment");
            var text = Descendants(shell).OfType<TextBlock>().Single(t => t.DataContext is TimelineHistoryItem { Chat.Message.Id: "c2" } && t.Name == "LinkedChatBody");
            var links = text.Inlines.OfType<Hyperlink>().ToArray();
            Check(links.Select(l => l.NavigateUri.AbsoluteUri).SequenceEqual(new[] { "https://example.com/a", "https://www.example.org/", "mailto:qa@example.net" }),
                "each body URL and email has its own native navigation target");
            text.SelectAll();
            Check(text.SelectedText == Body && text.IsTextSelectionEnabled, "selecting body text preserves Korean emoji newline and all links for copying");
            text.Select(text.ContentStart, text.ContentStart);
            shell.RequestedTheme = ElementTheme.Light; await Task.Delay(100);
            var linkedBody = Descendants(shell).OfType<UI.LinkedMessageText>().Single(t => t.DataContext is TimelineHistoryItem { Chat.Message.Id: "c2" });
            links = text.Inlines.OfType<Hyperlink>().ToArray();
            Check(links.All(l => l.Foreground == linkedBody.SentText), "own-message links stay readable in light theme");
            await RenderAsync(shell, "messenger-linked-text-light.png");
            shell.RequestedTheme = ElementTheme.Dark; await Task.Delay(100);
            await RenderAsync(shell, "messenger-linked-text-dark.png");
        }
        finally { await shell.DetachAsync(); window.CloseForQuit(); }
    }
}
#endif
