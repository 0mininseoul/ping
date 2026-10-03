using System.ComponentModel;
using System.Globalization;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Ping.Windows.Core.Models;
using VirtualKey = global::Windows.System.VirtualKey;

namespace Ping.Windows.App.Setup;

public sealed partial class RoomConnectionView : UserControl, IDisposable
{
    private readonly RoomSearchViewModel search;
    private readonly RoomManagerViewModel actions;
    private readonly Func<string?> currentRoomId;
    private readonly string? openingRoomId;
    private readonly Func<string> nickname;
    private readonly CancellationToken token;
    private readonly DispatcherQueueTimer debounce;
    private bool disposed;
    public bool IsSubmitting { get; private set; }
    public string? CompletedRoomId { get; private set; }
    public event EventHandler? Completed;

    public RoomConnectionView(RoomSearchViewModel search, RoomManagerViewModel actions,
        Func<string?> currentRoomId, Func<string> nickname, CancellationToken token, bool people = false)
    {
        this.search = search; this.actions = actions; this.currentRoomId = currentRoomId;
        this.nickname = nickname; this.token = token; openingRoomId = currentRoomId();
        InitializeComponent();
        debounce = DispatcherQueue.CreateTimer(); debounce.Interval = TimeSpan.FromMilliseconds(300); debounce.IsRepeating = false;
        debounce.Tick += DebounceTick;
        Root.DataContext = search;
        search.PropertyChanged += SearchUpdated;
        ResultsTabs.SelectedIndex = people ? 1 : 0;
        Loaded += (_, _) => { SearchBox.Focus(FocusState.Programmatic); UpdateEmpty(); };
    }
    private void QueryChanged(object sender, TextChangedEventArgs args)
    {
        if (debounce is null || disposed) return;
        debounce.Stop(); debounce.Start();
    }
    private async void DebounceTick(DispatcherQueueTimer sender, object args) => await SearchAsync();
    private async void SearchNow(object sender, RoutedEventArgs args) => await SearchAsync();
    private async void SearchKeyDown(object sender, KeyRoutedEventArgs args)
    { if (args.Key == VirtualKey.Enter) { args.Handled = true; await SearchAsync(); } }
    private async Task SearchAsync()
    {
        if (disposed || IsSubmitting) return;
        debounce.Stop(); OperationStatus.Text = ""; await search.SearchAsync(token); UpdateEmpty();
    }
    private void SearchUpdated(object? sender, PropertyChangedEventArgs args) => UpdateEmpty();
    private void TabChanged(object sender, SelectionChangedEventArgs args) { if (EmptyResults is not null) UpdateEmpty(); }
    private void UpdateEmpty()
    {
        if (disposed || EmptyResults is null) return;
        var count = ResultsTabs.SelectedIndex == 1 ? search.UserResults.Count : search.RoomResults.Count;
        EmptyResults.Visibility = count == 0 && !search.IsSearching ? Visibility.Visible : Visibility.Collapsed;
        EmptyResults.Text = string.IsNullOrWhiteSpace(search.Query) ? "검색어를 입력하세요"
            : ResultsTabs.SelectedIndex == 1 ? "검색된 사용자가 없습니다" : "열린 룸이 없습니다";
    }
    private void InviteLinkChanged(object sender, TextChangedEventArgs args)
    { if (JoinLinkButton is not null) JoinLinkButton.IsEnabled = PingInviteLink.TokenFrom(InviteLinkBox.Text) is not null; }
    private async void InviteLinkKeyDown(object sender, KeyRoutedEventArgs args)
    { if (args.Key == VirtualKey.Enter && JoinLinkButton.IsEnabled) { args.Handled = true; await JoinLinkAsync(); } }
    private async void JoinLink(object sender, RoutedEventArgs args) => await JoinLinkAsync();
    private async Task JoinLinkAsync()
    {
        if (PingInviteLink.TokenFrom(InviteLinkBox.Text) is null) return;
        await SubmitAsync("참여 중…", () => actions.AcceptInviteLinkAsync(InviteLinkBox.Text, token));
    }
    private async void JoinRoom(object sender, RoutedEventArgs args)
    {
        if (sender is not Button { Tag: RoomSearchRoomResult { CanJoin: true } row }) return;
        actions.SelectedSearchResult = row.Room;
        await SubmitAsync("참여 중…", () => actions.JoinSelectedSearchResultAsync(token));
    }
    private async void InviteUser(object sender, RoutedEventArgs args)
    {
        if (sender is not Button { Tag: RoomSearchUserResult { CanInvite: true } row }) return;
        if (currentRoomId() != openingRoomId)
        { OperationStatus.Text = "선택한 룸이 바뀌었어요. 창을 닫고 다시 시도하세요."; return; }
        actions.SelectedUserSearchResult = row.User;
        var name = DisplayText.NormalizeWhitespace($"{nickname()} ↔ {row.Nickname}");
        var elements = StringInfo.ParseCombiningCharacters(name);
        if (elements.Length > 16) name = name[..elements[16]];
        await SubmitAsync("초대 중…", () => actions.InviteSelectedUserAsync(name, token));
    }
    private async Task SubmitAsync(string status, Func<Task> work)
    {
        if (disposed || IsSubmitting || token.IsCancellationRequested) return;
        IsSubmitting = true; IsEnabled = false; debounce.Stop(); OperationStatus.Text = status;
        try
        {
            actions.ApplyProfileNickname(nickname());
            await work();
            if (disposed || token.IsCancellationRequested) return;
            CompletedRoomId = actions.SelectedRoom?.Id;
            Completed?.Invoke(this, EventArgs.Empty);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception ex) { if (!disposed) { actions.ReportError(ex); OperationStatus.Text = ex.Message; } }
        finally { IsSubmitting = false; if (!disposed) IsEnabled = true; }
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; debounce.Stop(); debounce.Tick -= DebounceTick;
        search.PropertyChanged -= SearchUpdated; search.Dispose();
    }
}
