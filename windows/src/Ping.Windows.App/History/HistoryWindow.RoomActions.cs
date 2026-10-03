using System.Globalization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.History;

public sealed partial class HistoryWindow
{
    private readonly CancellationTokenSource roomLifetime = new();
    private MessengerRoomServices? roomServices;
    private RoomManagerViewModel? roomActions;
    private bool roomActionOpen;
    private IReadOnlyList<Invitation> incomingInvitations = [];

    public void ApplyIncomingInvitations(IReadOnlyList<Invitation> invitations)
    {
        if (detached) return;
        var uid = roomServices?.CurrentUid();
        incomingInvitations = invitations.Where(item => item.ToUid == uid && item.ExpiresAt > DateTimeOffset.UtcNow).ToArray();
        InvitationsItems.ItemsSource = incomingInvitations;
        InvitationsPanel.Header = $"받은 초대 {incomingInvitations.Count}";
        InvitationsPanel.Visibility = incomingInvitations.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private async Task LoadInvitationsAsync()
    {
        if (roomServices is null || detached || roomServices.CurrentUid() is not { } uid) return;
        var result = await roomServices.Invitations.IncomingAsync(roomLifetime.Token);
        if (!detached && roomServices.CurrentUid() == uid) ApplyIncomingInvitations(result);
    }

    private async void AcceptInvitation_Click(object sender, RoutedEventArgs args) => await HandleInvitationAsync(sender, true);
    private async void RejectInvitation_Click(object sender, RoutedEventArgs args) => await HandleInvitationAsync(sender, false);
    private async Task HandleInvitationAsync(object sender, bool accept)
    {
        if (sender is not Button { Tag: Invitation { Id: { } id } invitation }
            || !incomingInvitations.Any(item => item.Id == id)) return;
        await RoomActionAsync(async () =>
        {
            if (accept)
            {
                await roomServices!.Invitations.AcceptAsync(id, roomServices.Nickname(), roomLifetime.Token);
                roomServices.RoomsChanged();
            }
            else await roomServices!.Invitations.RejectAsync(id, roomLifetime.Token);
            ApplyIncomingInvitations(incomingInvitations.Where(item => item.Id != id).ToArray());
            if (accept) await RefreshRoomsAfterActionAsync(invitation.RoomId);
        });
    }

    private void InitializeRoomActions(MessengerRoomServices? services)
    {
        roomServices = services;
        if (services is not null)
        {
            roomActions = new(services.Rooms, services.Invitations, services.Nickname(), clipboardWriter: services.Clipboard,
                userService: services.Users, currentUidProvider: services.CurrentUid);
            roomActions.RoomsChanged += (_, _) => { if (!detached) services.RoomsChanged(); };
        }
        UpdateRoomActionButtons();
    }

    private void UpdateRoomActionButtons()
    {
        if (MembersButton is null) return;
        var ready = !detached && backendReady && !roomActionOpen && roomServices?.CurrentUid() is not null;
        InvitationsPanel.IsEnabled = ready;
        CreateRoomButton.IsEnabled = SearchRoomsButton.IsEnabled = EmptyRoomButton.IsEnabled = ready;
        var selected = ready && viewModel.SelectedRoom?.Id is not null;
        MembersButton.IsEnabled = RenameRoomButton.IsEnabled = LeaveRoomButton.IsEnabled = selected;
        InviteLinkButton.IsEnabled = selected && viewModel.SelectedRoom!.MemberUids.Count < 8;
    }

    private void SynchronizeRoomActions()
    {
        roomActions!.ApplyProfileNickname(roomServices!.Nickname());
        roomActions.Rooms.Clear();
        foreach (var room in viewModel.Rooms) roomActions.Rooms.Add(room);
        roomActions.SelectedRoom = viewModel.SelectedRoom;
    }

    private async Task RoomActionAsync(Func<Task> action)
    {
        if (detached || !backendReady || roomActionOpen || roomServices?.CurrentUid() is null) return;
        roomActionOpen = true;
        UpdateRoomActionButtons();
        SynchronizeRoomActions();
        try { await RunAsync(action); }
        finally { roomActionOpen = false; UpdateRoomActionButtons(); }
    }

    private async Task RefreshRoomsAfterActionAsync(string? preferredRoomId)
    {
        if (detached || roomLifetime.IsCancellationRequested) return;
        await viewModel.LoadAsync(preferredRoomId, roomLifetime.Token);
        if (!detached) ApplySelectionFromViewModel();
    }

    private async void CreateRoom_Click(object sender, RoutedEventArgs args) => await RoomActionAsync(async () =>
    {
        if (await new RoomDialogs(Root, roomActions!).ShowRoomNameDialogAsync(true, roomLifetime.Token))
            await RefreshRoomsAfterActionAsync(roomActions!.SelectedRoom?.Id);
    });

    private async void RenameRoom_Click(object sender, RoutedEventArgs args) => await RoomActionAsync(async () =>
    {
        if (await new RoomDialogs(Root, roomActions!, () => viewModel.SelectedRoom?.Id)
            .ShowRoomNameDialogAsync(false, roomLifetime.Token))
            await RefreshRoomsAfterActionAsync(roomActions!.SelectedRoom?.Id);
    });

    private async void LeaveRoom_Click(object sender, RoutedEventArgs args) => await RoomActionAsync(async () =>
    {
        if (await new RoomDialogs(Root, roomActions!, () => viewModel.SelectedRoom?.Id).ShowLeaveDialogAsync(roomLifetime.Token))
            await RefreshRoomsAfterActionAsync(null);
    });

    private async void CopyInviteLink_Click(object sender, RoutedEventArgs args) => await RoomActionAsync(async () =>
    {
        var text = await roomActions!.CreateInviteLinkAsync(roomLifetime.Token);
        if (detached || text is null || roomActions.LastInviteLinkCopied) return;
        // Keep the link available even if the Windows clipboard is busy.
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot, RequestedTheme = Root.ActualTheme, Title = "초대 링크",
            Content = new TextBox { Text = text, IsReadOnly = true, TextWrapping = TextWrapping.Wrap }, CloseButtonText = "닫기"
        };
        var dispatcher = DispatcherQueue;
        using var registration = roomLifetime.Token.Register(() => dispatcher.TryEnqueue(() => dialog.Hide()));
        await dialog.ShowAsync();
    });

    private void MembersFlyout_Opening(object sender, object args)
    {
        if (viewModel.SelectedRoom is not { } room) return;
        var uid = roomServices?.CurrentUid();
        MembersTitle.Text = $"멤버 {room.MemberUids.Count}명";
        MembersItems.ItemsSource = room.MemberUids.OrderBy(id => id == uid ? 0 : 1).Select(id =>
        {
            var name = id == uid ? roomServices!.Nickname() : room.MemberNicknames.GetValueOrDefault(id, "멤버");
            if (string.IsNullOrWhiteSpace(name)) name = "멤버";
            return new RoomMemberRow(name, StringInfo.GetNextTextElement(name),
                string.Join(" · ", new[] { id == uid ? "나" : "", id == room.OwnerUid ? "방장" : "" }.Where(role => role.Length > 0)));
        }).ToArray();
    }
    private sealed record RoomMemberRow(string Nickname, string Initial, string Role);

    private async void SearchRooms_Click(object sender, RoutedEventArgs args) => await ShowRoomConnectionsAsync();
    private async void InvitePeople_Click(object sender, RoutedEventArgs args)
    { MembersFlyout.Hide(); await ShowRoomConnectionsAsync(people: true); }

    public async Task OpenRoomInvitationAsync(string roomId)
    {
        if (loadOnFirstLoaded) await (firstRoomLoad ??= ReloadRoomsAsync());
        if (await RunAsync(async () =>
        {
            await viewModel.LoadAsync(roomId, roomLifetime.Token);
            ApplySelectionFromViewModel();
        }) && viewModel.SelectedRoom?.Id == roomId)
            await ShowRoomConnectionsAsync(people: true);
    }

    private async Task ShowRoomConnectionsAsync(bool people = false) => await RoomActionAsync(async () =>
    {
        var services = roomServices!;
        if (!people) roomActions!.SelectedRoom = null;
        var search = new RoomSearchViewModel(services.Rooms, services.Users, services.CurrentUid, () => viewModel.Rooms);
        using var content = new RoomConnectionView(search, roomActions!, people ? () => viewModel.SelectedRoom?.Id : () => null,
            services.Nickname, roomLifetime.Token, people);
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot, RequestedTheme = Root.ActualTheme,
            Title = people ? "사람 초대" : "룸 · 사람 찾기", Content = content, CloseButtonText = "닫기"
        };
        content.Completed += (_, _) => dialog.Hide();
        dialog.Closing += (_, args) => args.Cancel = content.IsSubmitting && !roomLifetime.IsCancellationRequested
            && content.CompletedRoomId is null;
        var dispatcher = DispatcherQueue;
        using var registration = roomLifetime.Token.Register(() => dispatcher.TryEnqueue(() => dialog.Hide()));
        await dialog.ShowAsync();
        if (content.CompletedRoomId is { } roomId) await RefreshRoomsAfterActionAsync(roomId);
    });
}
