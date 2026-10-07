#if PING_UI_SMOKE
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.App.History;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    private static async Task VerifyChatLayoutAsync()
    {
        Step("Scoped chat layout fixture: synthetic messages only, no real account/backend/camera.");
        var rpc = new ChatLayoutRpc();
        var storage = new FixtureStorage();
        var vm = new HistoryViewModel(new RoomService(rpc), new MessageService(rpc, storage), new ChatMessageService(rpc),
            new ReactionService(rpc), storage, () => "me", new FixtureLinks(), _ => false);
        var window = new MainWindow();
        window.InitializeTrayWindowBehavior();
        TestDisplayPlacement.Verify(window, Check);
        var shell = new HistoryWindow(window, vm, (_, _) => throw new NotSupportedException(),
            (_, _) => Task.CompletedTask, new MessageService(rpc, storage), loadOnStart: false, refreshInterval: TimeSpan.FromHours(1));
        window.AttachMessenger(shell);
        window.ShowShell();
        try
        {
            await shell.ReloadRoomsAsync();
            ((FrameworkElement)window.Content).RequestedTheme = ElementTheme.Light;
            await Task.Delay(180);
            var list = (ListView)shell.FindName("VideosList");
            await UntilAsync(() => Descendants(list).OfType<ScrollViewer>().Any(), 5);
            var scroll = Descendants(list).OfType<ScrollViewer>().First();
            await UntilAsync(() => scroll.ScrollableHeight > 1000 && scroll.ScrollableHeight - scroll.VerticalOffset < 2, 5);
            Check(vm.Timeline.Count == 60, "long conversation loads all 60 synthetic messages");
            Check(scroll.ScrollableHeight - scroll.VerticalOffset < 2, "first room entry reaches newest message at actual bottom");
            Step($"Initial offset={scroll.VerticalOffset}; extent={scroll.ScrollableHeight}; viewport={scroll.ViewportHeight}");
            await RenderAsync((FrameworkElement)window.Content, "chat-latest-light.png");

            var newest = vm.Timeline.Last();
            list.SelectedItem = newest;
            await Task.Delay(180);
            var container = (FrameworkElement)list.ContainerFromItem(newest);
            var outline = Descendants(container).OfType<Border>().Single(b => b.Margin.Left == -3 && b.BorderThickness.Left == 1);
            Check(outline.Opacity > 0 && outline.ActualWidth < list.ActualWidth - 40,
                "selection outline follows message content instead of filling the timeline row");
            var presenter = Descendants(container).OfType<Microsoft.UI.Xaml.Controls.Primitives.ListViewItemPresenter>().Single();
            Check(presenter.SelectedBackground is SolidColorBrush brush && brush.Color.A == 0,
                "selected timeline row has no full-width filled rectangle");
            var sender = Descendants(container).OfType<TextBlock>().Single(t => t.Text == newest.SenderLabel);
            Check(sender.TextTrimming == TextTrimming.None && sender.TextWrapping == TextWrapping.Wrap
                && sender.ActualHeight >= 20 && sender.ActualWidth > 0,
                "long Korean nickname wraps with font height allowance and no ellipsis");
            await RenderAsync((FrameworkElement)window.Content, "chat-selection-light.png");
            ((FrameworkElement)window.Content).RequestedTheme = ElementTheme.Dark;
            await Task.Delay(180);
            await RenderAsync((FrameworkElement)window.Content, "chat-selection-dark.png");

            scroll.ChangeView(null, scroll.ScrollableHeight / 2, null, true);
            await Task.Delay(250);
            var readingOffset = scroll.VerticalOffset;
            double? RowY(TimelineHistoryItem row) => list.ContainerFromItem(row) is FrameworkElement element
                ? element.TransformToVisual(list).TransformPoint(new global::Windows.Foundation.Point()).Y : null;
            var anchor = vm.Timeline.First(row => list.ContainerFromItem(row) is FrameworkElement element
                && RowY(row) is { } y && y + element.ActualHeight > 0 && y < scroll.ViewportHeight);
            var anchorY = RowY(anchor)!.Value;
            Step($"Before unchanged refresh: offset={readingOffset}; extent={scroll.ScrollableHeight}");
            await vm.LoadSelectedRoomAsync();
            await Task.Delay(250);
            Step($"After unchanged refresh: offset={scroll.VerticalOffset}; extent={scroll.ScrollableHeight}");
            Check(Math.Abs(scroll.VerticalOffset - readingOffset) < 2,
                "unchanged refresh preserves position while reading older conversation");
            rpc.IncludeArrival = true;
            await vm.LoadSelectedRoomAsync();
            await Task.Delay(350);
            Step($"After arrival while reading: offset={scroll.VerticalOffset}; extent={scroll.ScrollableHeight}");
            Step($"Visible anchor {anchor.SortId}: beforeY={anchorY}; afterY={RowY(anchor)}");
            await RenderAsync((FrameworkElement)window.Content, "chat-arrival-while-reading.png");
            Check(RowY(anchor) is { } afterY && Math.Abs(afterY - anchorY) < 2,
                "new message preserves the older conversation viewport");

            await shell.FocusRoomAsync("layout-b");
            await UntilAsync(() => vm.SelectedRoom?.Id == "layout-b" && scroll.ScrollableHeight - scroll.VerticalOffset < 2, 5);
            await shell.FocusRoomAsync("layout-a");
            await UntilAsync(() => vm.SelectedRoom?.Id == "layout-a" && scroll.ScrollableHeight - scroll.VerticalOffset < 2, 5);
            Check(vm.Timeline.Last().SortId == "layout-a-arrival", "returning to a room reveals its newest arrival");
            await RenderAsync((FrameworkElement)window.Content, "chat-room-return-dark.png");
            window.AppWindow.Resize(new global::Windows.Graphics.SizeInt32(560, 540));
            await Task.Delay(250);
            var last = vm.Timeline.Last();
            list.SelectedItem = last;
            list.ScrollIntoView(last);
            await Task.Delay(250);
            Check(scroll.ScrollableWidth < 1, "minimum-size conversation has no horizontal scroll overflow");
            await RenderAsync((FrameworkElement)window.Content, "chat-minimum-dark.png");
        }
        finally { window.CloseForQuit(); }
    }

    private sealed class ChatLayoutRpc : ISupabaseRpcClient
    {
        internal bool IncludeArrival;
        private static readonly DateTimeOffset Epoch = new(2026, 10, 7, 8, 0, 0, TimeSpan.Zero);
        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            var room = body is RoomChatMessagesRpcBody chat ? chat.RoomUuid : "layout-a";
            object result = function switch
            {
                "ping_my_rooms" => new[] { MakeRoom("layout-a", "대화 디자인 확인"), MakeRoom("layout-b", "다른 방") },
                "ping_incoming_invitations" => Array.Empty<Invitation>(),
                "ping_room_messages" => Array.Empty<VideoMessage>(),
                "ping_message_reactions" => Array.Empty<MessageReaction>(),
                "ping_room_chat_messages" => Enumerable.Range(0, 60).Select(i => Message(room, i))
                    .Concat(IncludeArrival && room == "layout-a" ? new[] { Message(room, 60) with { Id = "layout-a-arrival" } } : Array.Empty<ChatMessage>()).ToArray(),
                _ => throw new NotSupportedException(function)
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }
        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default) => throw new NotSupportedException(function);
        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default) => Task.CompletedTask;
        private static Room MakeRoom(string id, string name) => new(id, name, name, "me", ["me", "peer"],
            new Dictionary<string, string> { ["me"] = "민지", ["peer"] = "서연" }, RoomStatus.Open);
        private static ChatMessage Message(string room, int index) => new()
        {
            Id = $"{room}-{index}", RoomId = room, SenderUid = index % 3 == 0 ? "me" : "peer",
            SenderNickname = index % 3 == 0 ? "민지" : "긴이름도끝까지자연스럽게보이는친구닉네임",
            Body = index == 59 || index == 60 ? "가장 최근 대화예요. 닉네임과 시간이 잘 보이고, 메시지를 선택해도 말풍선 크기에 맞아야 해요 😊"
                : index % 3 == 0 ? $"{index + 1}. 짧은 답장 😊" : $"{index + 1}. 지난 대화를 읽는 중에는 새로고침이나 새로운 메시지 때문에 스크롤 위치가 바뀌지 않아야 해요.",
            CreatedAt = Epoch.AddMinutes(index)
        };
    }
}
#endif
