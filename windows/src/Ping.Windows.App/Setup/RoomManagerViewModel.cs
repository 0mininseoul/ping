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
    private readonly IClipboardWriter clipboardWriter;
    private readonly Func<string, string> inviteLinkFormatter;
    private readonly Func<string?> currentUidProvider;
    private string nickname;
    private string statusMessage = "내 룸";
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
        this.nickname = NormalizeNickname(nickname);
        this.clipboardWriter = clipboardWriter ?? new ClipboardWriter();
        this.inviteLinkFormatter = inviteLinkFormatter ?? (token => PingInviteLink.ShareTextFor(token));
        this.currentUidProvider = currentUidProvider ?? (() => null);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public event EventHandler? RoomsChanged;

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
            OnPropertyChanged(nameof(CanMoveSelectedRoomUp));
            OnPropertyChanged(nameof(CanMoveSelectedRoomDown));
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

    public string SelectedRoomName => SelectedRoom?.Name ?? "룸을 선택하세요";

    public string SelectedRoomMembers =>
        SelectedRoom is null
            ? "새 룸을 만들거나 열린 룸에 참여하세요."
            : string.Join(", ", SelectedRoom.MemberNicknames.Values.OrderBy(value => value, StringComparer.OrdinalIgnoreCase));

    public bool CanMoveSelectedRoomUp =>
        SelectedRoom is not null && Rooms.IndexOf(SelectedRoom) > 0;

    public bool CanMoveSelectedRoomDown =>
        SelectedRoom is not null && Rooms.IndexOf(SelectedRoom) >= 0 && Rooms.IndexOf(SelectedRoom) < Rooms.Count - 1;

    public void ApplyProfileNickname(string updatedNickname)
    {
        var normalized = NormalizeNickname(updatedNickname);
        if (!string.IsNullOrWhiteSpace(normalized))
        {
            nickname = normalized;
        }
    }

    public async Task FocusRoomAsync(string roomId, CancellationToken cancellationToken = default)
    {
        SelectedRoom = Rooms.FirstOrDefault(room => room.Id == roomId);
        if (SelectedRoom is not null) return;
        await ReloadRoomsAsync(cancellationToken);
        SelectedRoom = Rooms.FirstOrDefault(room => room.Id == roomId);
    }

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        await ReloadRoomsAsync(cancellationToken);
        await ReloadInvitationsAsync(cancellationToken);
    }

    public async Task CreateRoomAsync(string roomName, CancellationToken cancellationToken = default)
    {
        var room = await roomService.CreateRoomAsync(roomName, nickname, cancellationToken);
        if (!Rooms.Any(candidate => candidate.Id == room.Id)) Rooms.Add(room);
        SelectedRoom = Rooms.First(candidate => candidate.Id == room.Id);
        RoomsChanged?.Invoke(this, EventArgs.Empty);
        try { await ReloadRoomsAsync(cancellationToken); }
        catch (Exception)
        {
            StatusMessage = $"{room.Name} 룸을 만들었어요. 목록은 다시 열 때 갱신됩니다.";
            return;
        }
        SelectedRoom = Rooms.FirstOrDefault(candidate => candidate.Id == room.Id) ?? room;
        StatusMessage = $"{room.Name} 룸을 만들었어요.";
    }

    public async Task SearchRoomsAsync(string prefix, CancellationToken cancellationToken = default)
    {
        SearchResults.Clear();
        SelectedSearchResult = null;
        foreach (var room in await roomService.SearchOpenRoomsAsync(prefix, cancellationToken))
        {
            SearchResults.Add(room);
        }

        StatusMessage = SearchResults.Count == 0 ? "검색한 룸이 없어요." : "참여할 룸을 선택하세요.";
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
        RoomsChanged?.Invoke(this, EventArgs.Empty);
        SelectedRoom = Rooms.FirstOrDefault(room => room.Id == roomId) ?? SelectedRoom;
        StatusMessage = $"{roomName} 룸에 참여했어요.";
    }

    public async Task RenameSelectedRoomAsync(string newName, CancellationToken cancellationToken = default)
    {
        if (SelectedRoom?.Id is not { } roomId)
        {
            return;
        }

        await roomService.RenameRoomAsync(roomId, newName, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        RoomsChanged?.Invoke(this, EventArgs.Empty);
        StatusMessage = "룸 이름을 변경했어요.";
    }

    public async Task LeaveSelectedRoomAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedRoom?.Id is not { } roomId)
        {
            return;
        }

        await roomService.LeaveRoomAsync(roomId, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        RoomsChanged?.Invoke(this, EventArgs.Empty);
        StatusMessage = "룸에서 나왔어요.";
    }

    public async Task MoveSelectedRoomAsync(int delta, CancellationToken cancellationToken = default)
    {
        if (SelectedRoom is not { } room)
        {
            return;
        }

        var currentIndex = Rooms.IndexOf(room);
        var newIndex = currentIndex + delta;
        if (currentIndex < 0 || newIndex < 0 || newIndex >= Rooms.Count)
        {
            return;
        }

        Rooms.Move(currentIndex, newIndex);
        var orderedRoomIds = Rooms
            .Select(candidate => candidate.Id)
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id!)
            .ToArray();

        await roomService.ReorderMyRoomsAsync(orderedRoomIds, cancellationToken).ConfigureAwait(false);
        SelectedRoom = room;
        RoomsChanged?.Invoke(this, EventArgs.Empty);
        StatusMessage = "룸 순서를 변경했어요.";
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
            StatusMessage = "초대를 보냈어요.";
            return;
        }

        var room = await invitationService.InviteUserAsync(userId.Trim(), nickname, fallbackRoomName, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        RoomsChanged?.Invoke(this, EventArgs.Empty);
        SelectedRoom = Rooms.FirstOrDefault(candidate => candidate.Id == room.Id) ?? room;
        StatusMessage = "새 룸에 초대했어요.";
    }

    public async Task SearchUsersAsync(string prefix, CancellationToken cancellationToken = default)
    {
        UserSearchResults.Clear();
        SelectedUserSearchResult = null;

        if (userService is null)
        {
            StatusMessage = "지금은 사람을 검색할 수 없어요.";
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
            ? "검색한 사람이 없어요."
            : "초대할 사람을 선택하세요.";
    }

    public async Task InviteSelectedUserAsync(string fallbackRoomName, CancellationToken cancellationToken = default)
    {
        if (SelectedUserSearchResult?.Id is not { Length: > 0 } userId)
        {
            StatusMessage = "초대할 사람을 선택하세요.";
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
        RoomsChanged?.Invoke(this, EventArgs.Empty);
        StatusMessage = "초대를 수락했어요.";
    }

    public async Task RejectSelectedInvitationAsync(CancellationToken cancellationToken = default)
    {
        if (SelectedInvitation?.Id is not { } invitationId)
        {
            return;
        }

        await invitationService.RejectAsync(invitationId, cancellationToken);
        await ReloadInvitationsAsync(cancellationToken);
        StatusMessage = "초대를 거절했어요.";
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
            ? "초대 링크를 복사했어요."
            : "초대 링크를 만들었어요. 찾기 탭에서 확인하세요.";
        return shareText;
    }

    public async Task AcceptInviteLinkAsync(string token, CancellationToken cancellationToken = default)
    {
        var inviteToken = PingInviteLink.TokenFrom(token);
        if (inviteToken is null)
        {
            StatusMessage = "올바른 초대 링크를 붙여넣으세요.";
            return;
        }

        var room = await invitationService.AcceptInviteLinkAsync(inviteToken, nickname, cancellationToken);
        await ReloadRoomsAsync(cancellationToken);
        RoomsChanged?.Invoke(this, EventArgs.Empty);
        SelectedRoom = Rooms.FirstOrDefault(candidate => candidate.Id == room.Id) ?? room;
        StatusMessage = $"{room.Name} 룸에 참여했어요.";
    }

    public void ReportError(Exception exception)
    {
        StatusMessage = exception.Message;
    }

    private async Task ReloadRoomsAsync(CancellationToken cancellationToken)
    {
        var previousSelectedId = SelectedRoom?.Id;
        var rooms = await roomService.MyRoomsAsync(cancellationToken);
        Rooms.Clear();
        foreach (var room in rooms)
        {
            Rooms.Add(room);
        }

        SelectedRoom = previousSelectedId is null
            ? Rooms.FirstOrDefault()
            : Rooms.FirstOrDefault(room => room.Id == previousSelectedId) ?? Rooms.FirstOrDefault();
    }

    private async Task ReloadInvitationsAsync(CancellationToken cancellationToken)
    {
        var previousSelectedId = SelectedInvitation?.Id;
        Invitations.Clear();
        foreach (var invitation in await invitationService.IncomingAsync(cancellationToken))
        {
            Invitations.Add(invitation);
        }

        SelectedInvitation = previousSelectedId is null
            ? Invitations.FirstOrDefault()
            : Invitations.FirstOrDefault(invitation => invitation.Id == previousSelectedId) ?? Invitations.FirstOrDefault();
    }

    private static string NormalizeNickname(string value) =>
        DisplayText.NormalizeWhitespace(value);

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

#if WINDOWS
public sealed partial class RoomManagerWindow : Window
{
    private readonly RoomManagerViewModel viewModel;
    private string? preferredRoomId;
    private Task? initialLoad;

    public RoomManagerWindow(RoomManagerViewModel viewModel)
    {
        this.viewModel = viewModel;
        InitializeComponent();
        Ping.Windows.App.UI.PingAppearance.Register(this);
        Ping.Windows.App.UI.WindowCaptureExclusion.Apply(this);
        Ping.Windows.App.UI.SettingsWindowGeometry.Fit(this, 640, 620);
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
    }

    public void RefreshProfileNickname(string nickname)
    {
        viewModel.ApplyProfileNickname(nickname);
    }

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        initialLoad ??= RunAsync(async () =>
        {
            await viewModel.LoadAsync();
            if (preferredRoomId is { } id) await viewModel.FocusRoomAsync(id);
        });
        await initialLoad;
    }

    internal async Task FocusRoomAsync(string roomId)
    {
        preferredRoomId = roomId;
        viewModel.SelectedRoom = null;
        if (!Root.IsLoaded) return;
        if (initialLoad is not null) await initialLoad;
        await RunAsync(() => viewModel.FocusRoomAsync(roomId));
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

    private async void CreateRoomButton_Click(object sender, RoutedEventArgs args) => await ShowRoomNameDialogAsync(true);

    private async void RenameRoomButton_Click(object sender, RoutedEventArgs args)
    {
        if (viewModel.SelectedRoom is not null) await ShowRoomNameDialogAsync(false);
    }

    private async Task ShowRoomNameDialogAsync(bool create)
    {
        var openingRoomId = viewModel.SelectedRoom?.Id;
        var input = new TextBox { Text = create ? "" : viewModel.SelectedRoomName, PlaceholderText = "룸 이름", CornerRadius = new(8) };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(input, create ? "새 룸 이름" : "룸 이름 변경");
        var error = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock { Text = "룸 이름을 16자 이내로 입력하세요.", TextWrapping = TextWrapping.Wrap });
        content.Children.Add(input); content.Children.Add(error);
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot, RequestedTheme = Root.ActualTheme,
            Title = create ? "새 룸 만들기" : "룸 이름 변경", Content = content,
            PrimaryButtonText = create ? "만들기" : "저장", CloseButtonText = "취소", DefaultButton = ContentDialogButton.Primary
        };
        var submitting = false;
        dialog.Closing += (_, args) => args.Cancel = submitting;
        dialog.PrimaryButtonClick += async (_, args) =>
        {
            if (!create && viewModel.SelectedRoom?.Id != openingRoomId)
            {
                args.Cancel = true; error.Text = "선택한 룸이 바뀌었어요. 창을 닫고 다시 시도하세요."; return;
            }
            var name = DisplayText.NormalizeWhitespace(input.Text);
            if (string.IsNullOrWhiteSpace(name) || System.Globalization.StringInfo.ParseCombiningCharacters(name).Length > 16)
            {
                args.Cancel = true; error.Text = "룸 이름을 1~16자로 입력하세요."; return;
            }
            var deferral = args.GetDeferral();
            submitting = true;
            dialog.IsPrimaryButtonEnabled = false;
            dialog.CloseButtonText = "";
            input.IsEnabled = false;
            try
            {
                if (create) await viewModel.CreateRoomAsync(name);
                else await viewModel.RenameSelectedRoomAsync(name);
            }
            catch (Exception ex) { args.Cancel = true; error.Text = ex.Message; viewModel.ReportError(ex); }
            finally
            {
                submitting = false; dialog.IsPrimaryButtonEnabled = true; dialog.CloseButtonText = "취소";
                input.IsEnabled = true; deferral.Complete();
            }
        };
        dialog.Opened += (_, _) => { input.Focus(FocusState.Programmatic); input.SelectAll(); };
        await dialog.ShowAsync();
    }

    private async void LeaveRoomButton_Click(object sender, RoutedEventArgs args)
    {
        if (viewModel.SelectedRoom is null) return;
        var openingRoomId = viewModel.SelectedRoom.Id;
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot, RequestedTheme = Root.ActualTheme, Title = "룸 나가기",
            Content = $"‘{viewModel.SelectedRoomName}’ 룸에서 나갑니다. 계속하시겠습니까?",
            PrimaryButtonText = "나가기", CloseButtonText = "취소", DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary && viewModel.SelectedRoom?.Id == openingRoomId)
            await RunAsync(() => viewModel.LeaveSelectedRoomAsync());
    }

    private async void MoveUpRoomButton_Click(object sender, RoutedEventArgs args)
    {
        if (sender is not MenuFlyoutItem { Tag: Room room }) return;
        viewModel.SelectedRoom = room;
        await RunAsync(() => viewModel.MoveSelectedRoomAsync(-1));
    }

    private async void MoveDownRoomButton_Click(object sender, RoutedEventArgs args)
    {
        if (sender is not MenuFlyoutItem { Tag: Room room }) return;
        viewModel.SelectedRoom = room;
        await RunAsync(() => viewModel.MoveSelectedRoomAsync(1));
    }

    private async void SearchButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.SearchRoomsAsync(SearchBox.Text));

    private async void JoinRoomButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.JoinSelectedSearchResultAsync());

    private async void SearchUsersButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.SearchUsersAsync(UserSearchBox.Text));

    private async void InviteSelectedUserButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.InviteSelectedUserAsync("새 룸"));

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
