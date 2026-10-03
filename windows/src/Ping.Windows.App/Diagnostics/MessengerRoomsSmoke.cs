#if PING_UI_SMOKE
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Ping.Windows.App.History;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Diagnostics;

internal static class MessengerRoomsSmoke
{
    public static async Task RunAsync(Action<bool, string> check, Func<FrameworkElement, string, Task> render)
    {
        var rpc = new RoomsRpc(); var storage = new NoStorage(); var clipboard = new OwnedClipboard();
        var window = new MainWindow(); window.InitializeTrayWindowBehavior();
        var vm = new HistoryViewModel(new(rpc), new(rpc, storage), new(rpc), new(rpc), storage, () => "me");
        var shell = new HistoryWindow(window, vm, (_, _) => throw new NotSupportedException(), (_, _) => Task.CompletedTask,
            new(rpc, storage), loadOnStart: false,
            roomServices: new(new(rpc), new(rpc), new(rpc), () => "me", () => "민", () => { }, clipboard));
        window.AttachMessenger(shell); window.ShowShell();
        try
        {
            await shell.ReloadRoomsAsync(); await Task.Delay(100);
            var root = (FrameworkElement)window.Content;
            check(((Button)shell.FindName("CreateRoomButton")).IsEnabled && ((Button)shell.FindName("RenameRoomButton")).IsEnabled,
                "messenger owns room creation and header management controls");
            ((Flyout)((Button)shell.FindName("MembersButton")).Flyout).ShowAt((Button)shell.FindName("MembersButton"));
            await Until(() => PopupNodes(root).OfType<TextBlock>().Any(t => t.Text == "서연"));
            check(PopupNodes(root).OfType<TextBlock>().Any(t => t.Text == "나 · 방장"), "member popover identifies nickname, self and owner without raw UID");
            await render(PopupNodes(root).OfType<StackPanel>().First(p => p.Width == 240), "messenger-members.png");
            ((Flyout)((Button)shell.FindName("MembersButton")).Flyout).Hide();
            await InvokeReady((Button)shell.FindName("InviteLinkButton"));
            await Until(() => clipboard.Text is not null);
            check(clipboard.Text!.Contains("owned-fixture-token-1234") && !PopupNodes(root).OfType<ContentDialog>().Any(),
                "header invite link copies through owned clipboard without another management window");

            await InvokeReady((Button)shell.FindName("CreateRoomButton"));
            var dialog = await Dialog(root);
            Nodes(dialog).OfType<TextBox>().Single().Text = "함께 쓰는 룸";
            await DialogButton(root, "만들기"); await Until(() => vm.SelectedRoom?.Id == "c");
            check(rpc.Creates == 1 && vm.Rooms.Any(r => r.Id == "c"), "main plus creates and selects the confirmed room once");
            var firstUseInvite = shell.OpenRoomInvitationAsync("c"); dialog = await Dialog(root);
            check(vm.SelectedRoom?.Id == "c" && dialog.Title?.ToString() == "사람 초대",
                "first-use completion opens invitation for the precise created conversation");
            await DialogButton(root, "닫기"); await firstUseInvite;

            await InvokeReady((Button)shell.FindName("SearchRoomsButton")); dialog = await Dialog(root);
            var connection = (RoomConnectionView)dialog.Content;
            var searchBox = (TextBox)connection.FindName("SearchBox"); searchBox.Text = "같은";
            await Until(() => ((ListView)connection.FindName("RoomResultsList")).Items.Count == 3);
            await Until(() => Nodes(connection).OfType<Button>().Count(b => b.Tag is RoomSearchRoomResult) == 3);
            check(rpc.SearchReads == 1 && Nodes(connection).OfType<Button>().Any(b => b.Content?.ToString() == "내 룸" && !b.IsEnabled),
                "300ms native search updates joined room flags without explicit submission");
            check(Nodes(connection).OfType<TextBlock>().Any(t => t.Text == "방장: 지우")
                && Nodes(connection).OfType<TextBlock>().Any(t => t.Text == "방장: 수진"), "same-name search rooms remain distinguishable by owner nickname");
            await Task.Delay(250); await render(dialog, "messenger-search.png");
            rpc.FailSearch = true; Invoke((Button)connection.FindName("SearchButton"));
            await Until(() => ((TextBlock)connection.FindName("SearchError")).Text == "검색 연결 실패");
            check(searchBox.Text == "같은", "native search failure preserves the entered query");
            rpc.FailSearch = false; Invoke((Button)connection.FindName("SearchButton"));
            await Until(() => ((ListView)connection.FindName("RoomResultsList")).Items.Count == 3);
            Invoke(Nodes(connection).OfType<Button>().Single(b => b.Tag is RoomSearchRoomResult { Room.Id: "d" }));
            await Until(() => vm.SelectedRoom?.Id == "d");
            check(rpc.Joins == 1, "search row joins its own room and returns directly to that conversation");

            await InvokeReady((Button)shell.FindName("SearchRoomsButton")); dialog = await Dialog(root); connection = (RoomConnectionView)dialog.Content;
            ((Pivot)connection.FindName("ResultsTabs")).SelectedIndex = 1;
            ((TextBox)connection.FindName("SearchBox")).Text = "지우";
            await Until(() => ((ListView)connection.FindName("UserResultsList")).Items.Count == 2);
            check(!((ListView)connection.FindName("UserResultsList")).Items.Cast<RoomSearchUserResult>().Any(r => r.User.Id == "me"),
                "native people search excludes the active account");
            await Until(() => Nodes(connection).OfType<Button>().Any(b => b.Tag is RoomSearchUserResult { User.Id: "new" }));
            await Task.Delay(250); await render(dialog, "messenger-people.png");
            Invoke(Nodes(connection).OfType<Button>().Single(b => b.Tag is RoomSearchUserResult { User.Id: "new" }));
            await Until(() => vm.SelectedRoom?.Id == "g");
            check(rpc.DirectInvited == "new" && rpc.Invited is null,
                "global person search creates a direct connection instead of inviting into the viewed room");

            await shell.FocusRoomAsync("d");
            ((Flyout)((Button)shell.FindName("MembersButton")).Flyout).ShowAt((Button)shell.FindName("MembersButton"));
            await Until(() => PopupNodes(root).OfType<Button>().Any(b => b.Content?.ToString() == "사람 초대"));
            Invoke(PopupNodes(root).OfType<Button>().Single(b => b.Content?.ToString() == "사람 초대"));
            dialog = await Dialog(root); connection = (RoomConnectionView)dialog.Content;
            check(((Pivot)connection.FindName("ResultsTabs")).SelectedIndex == 1, "member popover invitation opens people tab for that room");
            ((TextBox)connection.FindName("SearchBox")).Text = "지우";
            await Until(() => Nodes(connection).OfType<Button>().Any(b => b.Tag is RoomSearchUserResult { User.Id: "new" }));
            Invoke(Nodes(connection).OfType<Button>().Single(b => b.Tag is RoomSearchUserResult { User.Id: "new" }));
            await Until(() => rpc.Invited == "new"); await Until(() => !PopupNodes(root).OfType<ContentDialog>().Any()); await Task.Delay(50);
            check(vm.SelectedRoom?.Id == "d" && rpc.InvitedRoom == "d", "member invitation keeps and targets its existing room");

            await InvokeReady((Button)shell.FindName("SearchRoomsButton")); dialog = await Dialog(root); connection = (RoomConnectionView)dialog.Content;
            ((TextBox)connection.FindName("InviteLinkBox")).Text = "owned-fixture-token-1234";
            await InvokeReady((Button)connection.FindName("JoinLinkButton")); await Until(() => vm.SelectedRoom?.Id == "e");
            check(rpc.LinkJoins == 1, "invite code acceptance opens its returned room inside the messenger");

            await InvokeReady((Button)shell.FindName("RenameRoomButton")); dialog = await Dialog(root);
            var input = Nodes(dialog).OfType<TextBox>().Single(); input.Text = "다른 룸에 적용 금지";
            ((ListView)shell.FindName("RoomsList")).SelectedItem = vm.Rooms.Single(r => r.Id == "b");
            await Until(() => vm.SelectedRoom?.Id == "b");
            await DialogButton(root, "저장");
            check(rpc.Rename is null && PopupNodes(root).OfType<TextBlock>().Any(t => t.Text.Contains("선택한 룸이 바뀌었어요")),
                "messenger rename dialog cannot mutate a different selected room");
            await DialogButton(root, "취소");
            await Until(() => !PopupNodes(root).OfType<ContentDialog>().Any()); await Task.Delay(50);
            await InvokeReady((Button)shell.FindName("RenameRoomButton")); dialog = await Dialog(root);
            Nodes(dialog).OfType<TextBox>().Single().Text = "새로운 이름";
            await DialogButton(root, "저장"); await Until(() => vm.SelectedRoom?.Name == "새로운 이름");
            check(rpc.Rename is { RoomUuid: "b", NewName: "새로운 이름" }, "header rename targets and refreshes the same room");

            await InvokeReady((Button)shell.FindName("LeaveRoomButton")); await Dialog(root);
            ((ListView)shell.FindName("RoomsList")).SelectedItem = vm.Rooms.Single(r => r.Id == "a");
            await Until(() => vm.SelectedRoom?.Id == "a"); await DialogButton(root, "나가기");
            check(rpc.Left is null, "messenger leave confirmation cannot remove a room selected later");
            await Until(() => !PopupNodes(root).OfType<ContentDialog>().Any()); await Task.Delay(50);
            await InvokeReady((Button)shell.FindName("LeaveRoomButton")); await Dialog(root); await DialogButton(root, "나가기");
            await Until(() => !vm.Rooms.Any(r => r.Id == "a"));
            check(rpc.Left == "a", "confirmed room leave removes it from the messenger sidebar");

            ((Expander)shell.FindName("InvitationsPanel")).IsExpanded = true;
            await Until(() => Nodes(root).OfType<Button>().Any(b => b.Tag is Invitation { Id: "invite" } && b.Content?.ToString() == "수락"));
            Invoke(Nodes(root).OfType<Button>().Single(b => b.Tag is Invitation { Id: "invite" } && b.Content?.ToString() == "수락"));
            await Until(() => vm.SelectedRoom?.Id == "f");
            check(rpc.Accepted == "invite" && ((Expander)shell.FindName("InvitationsPanel")).Visibility == Visibility.Collapsed,
                "received invitation accepts in the sidebar and opens the invited room");
            shell.ApplyIncomingInvitations([
                new Invitation("reject", "peer", "me", "other", "수진", "다른 룸", null, DateTimeOffset.UtcNow.AddDays(1)),
                new Invitation("foreign", "peer", "another-user", "other", "수진", "다른 계정", null, DateTimeOffset.UtcNow.AddDays(1)),
                new Invitation("expired", "peer", "me", "other", "수진", "만료", null, DateTimeOffset.UtcNow.AddSeconds(-1))]);
            check(((ItemsControl)shell.FindName("InvitationsItems")).Items.Count == 1, "sidebar excludes expired and other-account invitations");
            ((Expander)shell.FindName("InvitationsPanel")).IsExpanded = true;
            await Until(() => Nodes(root).OfType<Button>().Any(b => b.Tag is Invitation { Id: "reject" } && b.Content?.ToString() == "거절"));
            Invoke(Nodes(root).OfType<Button>().Single(b => b.Tag is Invitation { Id: "reject" } && b.Content?.ToString() == "거절"));
            await Until(() => rpc.Rejected == "reject");
            check(vm.SelectedRoom?.Id == "f" && ((ItemsControl)shell.FindName("InvitationsItems")).Items.Count == 0,
                "sidebar rejection removes only its invitation and preserves the viewed room");
            await render(root, "messenger-integrated.png");

            var face = 0; var screen = 0;
            shell.FacePingRequested += (_, _) => face++; shell.ScreenPingRequested += (_, _) => screen++;
            var captureButton = (Button)shell.FindName("ComposeMenuButton"); var captureMenu = (MenuFlyout)captureButton.Flyout;
            captureMenu.ShowAt(captureButton); await Task.Delay(50);
            ((IInvokeProvider)new MenuFlyoutItemAutomationPeer(captureMenu.Items.OfType<MenuFlyoutItem>().Single(i => i.Text.Contains("얼굴 핑"))).GetPattern(PatternInterface.Invoke)).Invoke();
            captureMenu.ShowAt(captureButton); await Task.Delay(50);
            ((IInvokeProvider)new MenuFlyoutItemAutomationPeer(captureMenu.Items.OfType<MenuFlyoutItem>().Single(i => i.Text.Contains("화면 + 얼굴"))).GetPattern(PatternInterface.Invoke)).Invoke();
            check(face == 1 && screen == 1, "compact compose menu preserves actual face and screen recording entry points");
            captureMenu.Hide();

            await InvokeReady((Button)shell.FindName("SearchRoomsButton")); await Dialog(root);
            await shell.DetachAsync();
            await Until(() => !PopupNodes(root).OfType<ContentDialog>().Any());
            check(!shell.IsEnabled, "account runtime detachment cancels and closes an open room search dialog");
        }
        catch (Exception error)
        {
            File.WriteAllText(Path.Combine(UiSmokeRunner.OutputDirectory!, "messenger-room-failure.txt"), error.ToString());
            throw;
        }
        finally { await shell.DetachAsync(); window.CloseForQuit(); }
    }

    private static async Task InvokeReady(Button button) { await Until(() => button.IsEnabled); Invoke(button); }
    private static void Invoke(Button button) => ((IInvokeProvider)new ButtonAutomationPeer(button).GetPattern(PatternInterface.Invoke)).Invoke();
    private static IEnumerable<DependencyObject> Nodes(DependencyObject root)
    {
        yield return root;
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
            foreach (var item in Nodes(VisualTreeHelper.GetChild(root, i))) yield return item;
    }
    private static IEnumerable<DependencyObject> PopupNodes(FrameworkElement root) =>
        VisualTreeHelper.GetOpenPopupsForXamlRoot(root.XamlRoot).SelectMany(p => Nodes(p.Child));
    private static async Task Until(Func<bool> predicate)
    {
        var deadline = DateTime.UtcNow.AddSeconds(3);
        while (!predicate()) { if (DateTime.UtcNow > deadline) throw new TimeoutException("Messenger action did not settle."); await Task.Delay(20); }
    }
    private static async Task<ContentDialog> Dialog(FrameworkElement root)
    {
        ContentDialog? dialog = null;
        await Until(() => (dialog = PopupNodes(root).OfType<ContentDialog>().FirstOrDefault()) is not null);
        await Task.Delay(50); return dialog!;
    }
    private static async Task DialogButton(FrameworkElement root, string text)
    {
        Button? button = null;
        await Until(() => (button = PopupNodes(root).OfType<Button>().FirstOrDefault(b => b.Content?.ToString() == text && b.IsEnabled)) is not null);
        Invoke(button!); await Task.Delay(80);
    }
    private sealed class OwnedClipboard : IClipboardWriter
    {
        public string? Text;
        public Task<bool> TrySetTextAsync(string text, CancellationToken cancellationToken = default)
        { Text = text; return Task.FromResult(true); }
    }
    private sealed class RoomsRpc : ISupabaseRpcClient
    {
        public List<Room> Rooms = [Room("a", "디자인 이야기"), Room("b", "오늘의 작은 순간")];
        public int SearchReads, Creates, Joins, LinkJoins;
        public RenameRoomRpcBody? Rename;
        public string? Left, Invited, InvitedRoom, DirectInvited, Accepted, Rejected;
        public bool FailSearch;
        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            object result = function switch
            {
                "ping_my_rooms" => Rooms.ToArray(),
                "ping_incoming_invitations" => Accepted is null ? new[] { new Invitation("invite", "peer", "me", "f", "지우", "함께 이야기", null, DateTimeOffset.UtcNow.AddDays(1)) } : [],
                "ping_room_messages" => Array.Empty<VideoMessage>(), "ping_room_chat_messages" => Array.Empty<ChatMessage>(),
                "ping_message_reactions" => Array.Empty<MessageReaction>(),
                "ping_search_open_rooms" => SearchRooms(),
                "ping_search_profiles" => new[] { new PingUser("me", "민", "민", ["a"], "a"), new PingUser("peer", "서연", "서연", ["a"], "a"), new PingUser("new", "지우", "지우", [], null) },
                "ping_create_room" => Create((CreateRoomRpcBody)body!),
                "ping_create_invite_link" => new[] { new InviteLink("owned-fixture-token-1234", "a", "디자인 이야기", "민", DateTimeOffset.UtcNow.AddDays(1)) },
                "ping_accept_invite_link" => JoinLink(),
                "ping_invite_user" => DirectInvite((InviteUserRpcBody)body!),
                _ => throw new NotSupportedException(function)
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }
        private Room[] SearchRooms()
        {
            SearchReads++; if (FailSearch) throw new InvalidOperationException("검색 연결 실패");
            return [Rooms.First(r => r.Id == "a"), Room("d", "같은 이름", "지우"), Room("other", "같은 이름", "수진")];
        }
        private Room[] Create(CreateRoomRpcBody body) { Creates++; var room = Room("c", body.RoomName); Rooms.Add(room); return [room]; }
        private Room[] JoinLink() { LinkJoins++; var room = Room("e", "링크로 참여"); Rooms.Add(room); return [room]; }
        private Room[] DirectInvite(InviteUserRpcBody body) { DirectInvited = body.TargetUid; var room = Room("g", "민 ↔ 지우"); Rooms.Add(room); return [room]; }
        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function == "ping_send_invitation") { var invitation = (SendInvitationRpcBody)body!; Invited = invitation.ToUid; InvitedRoom = invitation.RoomUuid; }
            else throw new NotSupportedException(function);
            return Task.FromResult((T)(object)"invitation-result");
        }
        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function == "ping_rename_room") { Rename = (RenameRoomRpcBody)body!; var index = Rooms.FindIndex(r => r.Id == Rename.RoomUuid); Rooms[index] = Rooms[index] with { Name = Rename.NewName }; }
            if (function == "ping_leave_room") { Left = ((RoomIdRpcBody)body!).RoomUuid; Rooms.RemoveAll(r => r.Id == Left); }
            if (function == "ping_join_room") { Joins++; Rooms.Add(Room(((JoinRoomRpcBody)body!).RoomUuid, "같은 이름")); }
            if (function == "ping_accept_invitation") { Accepted = ((AcceptInvitationRpcBody)body!).InvitationUuid; Rooms.Add(Room("f", "함께 이야기")); }
            if (function == "ping_reject_invitation") Rejected = ((InvitationIdRpcBody)body!).InvitationUuid;
            return Task.CompletedTask;
        }
        private static Room Room(string id, string name, string? ownerName = null) => new(id, name, name, ownerName is null ? "me" : "owner-" + id,
            ownerName is null ? ["me", "peer"] : ["owner-" + id],
            ownerName is null ? new Dictionary<string, string> { ["me"] = "민", ["peer"] = "서연" } : new Dictionary<string, string> { ["owner-" + id] = ownerName }, RoomStatus.Open);
    }
    private sealed class NoStorage : IStorageService, IChatMediaStorageService
    {
        public Task<string> UploadVideoAsync(string localVideoPath, string senderUid, string videoId, IReadOnlyCollection<string> authorizedReceiverUids, DateTimeOffset expiresAt, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task DeleteVideoAsync(string remotePath, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<ChatImageUpload> UploadChatImageAsync(string localImagePath, string senderUid, string messageId, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<string> DownloadChatMediaAsync(string remotePath, string fileExtension, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task DeleteChatMediaAsync(string remotePath, CancellationToken cancellationToken = default) => throw new NotSupportedException();
    }
}
#endif
