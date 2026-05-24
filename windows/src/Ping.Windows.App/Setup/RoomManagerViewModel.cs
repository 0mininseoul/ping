using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
#endif

namespace Ping.Windows.App.Setup;

public sealed class RoomManagerViewModel : INotifyPropertyChanged
{
    private readonly RoomService roomService;
    private readonly InvitationService invitationService;
    private readonly UserService? userService;
    private readonly string nickname;
    private readonly IClipboardWriter clipboardWriter;
    private readonly Func<string, string> inviteLinkFormatter;
    private readonly Func<string?> currentUidProvider;
    private string statusMessage = "Rooms";
    private Room? selectedRoom;
    private Room? selectedSearchResult;
    private PingUser? selectedUserSearchResult;
    private Invitation? selectedInvitation;

    public RoomManagerViewModel(
        RoomService roomService,
        InvitationService invitationService,
        string nickname,
        IClipboardWriter? clipboardWriter = null,
        Func<string, string>? inviteLinkFormatter = null,
        UserService? userService = null,
        Func<string?>? currentUidProvider = null)
    {
        this.roomService = roomService;
        this.invitationService = invitationService;
        this.userService = userService;
        this.nickname = nickname;
        this.clipboardWriter = clipboardWriter ?? new ClipboardWriter();
        this.inviteLinkFormatter = inviteLinkFormatter ?? (token => PingInviteLink.ShareTextFor(token));
        this.currentUidProvider = currentUidProvider ?? (() => null);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<Room> Rooms { get; } = [];

    public ObservableCollection<Room> SearchResults { get; } = [];

    public ObservableCollection<PingUser> UserSearchResults { get; } = [];

    public ObservableCollection<Invitation> Invitations { get; } = [];

    public string StatusMessage
    {
        get => statusMessage;
        private set
        {
            if (string.Equals(statusMessage, value, StringComparison.Ordinal))
            {
                return;
            }

            statusMessage = value;
            OnPropertyChanged();
        }
    }

    public Room? SelectedRoom
    {
        get => selectedRoom;
        set
        {
            if (Equals(selectedRoom, value))
            {
                return;
            }

            selectedRoom = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(SelectedRoomName));
            OnPropertyChanged(nameof(SelectedRoomMembers));
        }
    }

    public Room? SelectedSearchResult
    {
        get => selectedSearchResult;
        set
        {
            selectedSearchResult = value;
            OnPropertyChanged();
        }
    }

    public Invitation? SelectedInvitation
    {
        get => selectedInvitation;
        set
        {
            selectedInvitation = value;
            OnPropertyChanged();
        }
    }

    public PingUser? SelectedUserSearchResult
    {
        get => selectedUserSearchResult;
        set
        {
            selectedUserSearchResult = value;
            OnPropertyChanged();
        }
    }

    public string SelectedRoomName => SelectedRoom?.Name ?? "No room selected";

    public string SelectedRoomMembers =>
        SelectedRoom is null
            ? "Create, join, or select a room."
            : string.Join(", ", SelectedRoom.MemberNicknames.Values.OrderBy(value => value, StringComparer.OrdinalIgnoreCase));

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        await ReloadRoomsAsync(cancellationToken);
        await ReloadInvitationsAsync(cancellationToken);
    }

    public async Task CreateRoomAsync(string roomName, CancellationToken cancellationToken = default)
    {
        var room = await roomService.CreateRoomAsync(roomName, nickname, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        SelectedRoom = Rooms.FirstOrDefault(candidate => candidate.Id == room.Id) ?? room;
        StatusMessage = $"Created {room.Name}.";
    }

    public async Task SearchRoomsAsync(string prefix, CancellationToken cancellationToken = default)
    {
        SearchResults.Clear();
        foreach (var room in await roomService.SearchOpenRoomsAsync(prefix, cancellationToken))
        {
            SearchResults.Add(room);
        }

        StatusMessage = SearchResults.Count == 0 ? "No matching open rooms." : "Select a room to join.";
    }

    public async Task JoinSelectedSearchResultAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedSearchResult?.Id is not { } roomId)
        {
            return;
        }

        var roomName = SelectedSearchResult.Name;
        await roomService.JoinRoomAsync(roomId, nickname, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        SelectedRoom = Rooms.FirstOrDefault(room => room.Id == roomId) ?? SelectedRoom;
        StatusMessage = $"Joined {roomName}.";
    }

    public async Task RenameSelectedRoomAsync(string newName, CancellationToken cancellationToken = default)
    {
        if (SelectedRoom?.Id is not { } roomId)
        {
            return;
        }

        await roomService.RenameRoomAsync(roomId, newName, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        StatusMessage = "Room renamed.";
    }

    public async Task LeaveSelectedRoomAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedRoom?.Id is not { } roomId)
        {
            return;
        }

        await roomService.LeaveRoomAsync(roomId, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        StatusMessage = "Left room.";
    }

    public async Task InviteUserAsync(string userId, string fallbackRoomName, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(userId))
        {
            return;
        }

        if (SelectedRoom?.Id is { } roomId)
        {
            await invitationService.SendAsync(userId.Trim(), roomId, nickname, SelectedRoom.Name, cancellationToken);
            StatusMessage = "Invitation sent.";
            return;
        }

        var room = await invitationService.InviteUserAsync(userId.Trim(), nickname, fallbackRoomName, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        SelectedRoom = Rooms.FirstOrDefault(candidate => candidate.Id == room.Id) ?? room;
        StatusMessage = "Invitation sent in a new room.";
    }

    public async Task SearchUsersAsync(string prefix, CancellationToken cancellationToken = default)
    {
        UserSearchResults.Clear();
        SelectedUserSearchResult = null;

        if (userService is null)
        {
            StatusMessage = "User search is unavailable.";
            return;
        }

        var currentUid = currentUidProvider();
        foreach (var user in await userService.SearchByNicknamePrefixAsync(prefix, cancellationToken))
        {
            if (!string.Equals(user.Id, currentUid, StringComparison.Ordinal))
            {
                UserSearchResults.Add(user);
            }
        }

        StatusMessage = UserSearchResults.Count == 0
            ? "No matching users."
            : "Select a user to invite.";
    }

    public async Task InviteSelectedUserAsync(string fallbackRoomName, CancellationToken cancellationToken = default)
    {
        if (SelectedUserSearchResult?.Id is not { Length: > 0 } userId)
        {
            StatusMessage = "Select a user to invite.";
            return;
        }

        await InviteUserAsync(userId, fallbackRoomName, cancellationToken);
    }

    public async Task AcceptSelectedInvitationAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedInvitation?.Id is not { } invitationId)
        {
            return;
        }

        await invitationService.AcceptAsync(invitationId, nickname, cancellationToken);
        await LoadAsync(cancellationToken);
        StatusMessage = "Invitation accepted.";
    }

    public async Task RejectSelectedInvitationAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedInvitation?.Id is not { } invitationId)
        {
            return;
        }

        await invitationService.RejectAsync(invitationId, cancellationToken);
        await ReloadInvitationsAsync(cancellationToken);
        StatusMessage = "Invitation rejected.";
    }

    public async Task<string?> CreateInviteLinkAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedRoom?.Id is not { } roomId)
        {
            return null;
        }

        var link = await invitationService.CreateInviteLinkAsync(roomId, cancellationToken);
        var shareText = inviteLinkFormatter(link.Token);
        var didCopy = await clipboardWriter.TrySetTextAsync(shareText, cancellationToken);
        StatusMessage = didCopy
            ? "Invite link copied to clipboard."
            : "Invite link created in the field.";
        return shareText;
    }

    public async Task AcceptInviteLinkAsync(string token, CancellationToken cancellationToken = default)
    {
        var inviteToken = PingInviteLink.TokenFrom(token);
        if (inviteToken is null)
        {
            StatusMessage = "Paste a valid invite link or token.";
            return;
        }

        var room = await invitationService.AcceptInviteLinkAsync(inviteToken, nickname, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        SelectedRoom = Rooms.FirstOrDefault(candidate => candidate.Id == room.Id) ?? room;
        StatusMessage = $"Joined {room.Name}.";
    }

    public void ReportError(Exception exception)
    {
        StatusMessage = exception.Message;
    }

    private async Task ReloadRoomsAsync(CancellationToken cancellationToken)
    {
        var previousSelectedId = SelectedRoom?.Id;
        Rooms.Clear();
        foreach (var room in (await roomService.MyRoomsAsync(cancellationToken)).OrderBy(room => room.Name, StringComparer.OrdinalIgnoreCase))
        {
            Rooms.Add(room);
        }

        SelectedRoom = previousSelectedId is null
            ? Rooms.FirstOrDefault()
            : Rooms.FirstOrDefault(room => room.Id == previousSelectedId) ?? Rooms.FirstOrDefault();
    }

    private async Task ReloadInvitationsAsync(CancellationToken cancellationToken)
    {
        Invitations.Clear();
        foreach (var invitation in await invitationService.IncomingAsync(cancellationToken))
        {
            Invitations.Add(invitation);
        }
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

#if WINDOWS
public sealed partial class RoomManagerWindow : Window
{
    private readonly RoomManagerViewModel viewModel;

    public RoomManagerWindow(RoomManagerViewModel viewModel)
    {
        this.viewModel = viewModel;
        InitializeComponent();
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
    }

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        await RunAsync(() => viewModel.LoadAsync());
    }

    private void HandleRoomSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        viewModel.SelectedRoom = RoomsList.SelectedItem as Room;
    }

    private void HandleSearchSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        viewModel.SelectedSearchResult = SearchResultsList.SelectedItem as Room;
    }

    private void HandleUserSearchSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        viewModel.SelectedUserSearchResult = UserSearchResultsList.SelectedItem as PingUser;
    }

    private void HandleInvitationSelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        viewModel.SelectedInvitation = InvitationsList.SelectedItem as Invitation;
    }

    private async void CreateRoomButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.CreateRoomAsync(NewRoomNameBox.Text));

    private async void RenameRoomButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.RenameSelectedRoomAsync(RenameRoomBox.Text));

    private async void LeaveRoomButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.LeaveSelectedRoomAsync());

    private async void SearchButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.SearchRoomsAsync(SearchBox.Text));

    private async void JoinRoomButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.JoinSelectedSearchResultAsync());

    private async void InviteUserButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.InviteUserAsync(InviteUserIdBox.Text, NewRoomNameBox.Text));

    private async void SearchUsersButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.SearchUsersAsync(UserSearchBox.Text));

    private async void InviteSelectedUserButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.InviteSelectedUserAsync(NewRoomNameBox.Text));

    private async void AcceptInvitationButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.AcceptSelectedInvitationAsync());

    private async void RejectInvitationButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.RejectSelectedInvitationAsync());

    private async void CreateInviteLinkButton_Click(object sender, RoutedEventArgs args)
    {
        await RunAsync(async () =>
        {
            var token = await viewModel.CreateInviteLinkAsync();
            if (token is not null)
            {
                InviteLinkTokenBox.Text = token;
            }
        });
    }

    private async void AcceptInviteLinkButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.AcceptInviteLinkAsync(InviteLinkTokenBox.Text));

    private async Task RunAsync(Func<Task> work)
    {
        try
        {
            await work();
        }
        catch (Exception ex)
        {
            viewModel.ReportError(ex);
        }
    }
}

#endif
