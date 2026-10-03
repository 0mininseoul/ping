using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Setup;

public sealed record RoomSearchRoomResult(Room Room, bool CanJoin)
{
    public string Name => Room.Name;
    public string OwnerNicknameLabel => Room.OwnerNicknameLabel;
    public string ActionLabel => CanJoin ? "참여 요청" : "내 룸";
}

public sealed record RoomSearchUserResult(PingUser User, bool CanInvite)
{
    public string Nickname => User.Nickname;
    public string RoomsLabel => User.Rooms.Count == 0 ? "참여 중인 룸 없음" : $"룸 {User.Rooms.Count}개";
    public string ActionLabel => CanInvite ? "초대" : "내 룸";
}

public sealed class RoomSearchViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly RoomService roomService;
    private readonly UserService userService;
    private readonly Func<string?> currentUid;
    private readonly Func<IReadOnlyList<Room>> myRooms;
    private CancellationTokenSource? activeSearch;
    private int generation;
    private bool disposed;
    private string query = "", error = "";
    private bool searching;
    public RoomSearchViewModel(RoomService rooms, UserService users, Func<string?> currentUid,
        Func<IReadOnlyList<Room>> myRooms)
    { roomService = rooms; userService = users; this.currentUid = currentUid; this.myRooms = myRooms; }
    public event PropertyChangedEventHandler? PropertyChanged;
    public string Query
    {
        get => query;
        set
        {
            if (query == value || disposed) return;
            query = value; generation++; activeSearch?.Cancel(); IsSearching = false; Error = "";
            if (string.IsNullOrWhiteSpace(value)) { RoomResults.Clear(); UserResults.Clear(); }
            Notify();
        }
    }
    public string Error { get => error; private set { error = value; Notify(); } }
    public bool IsSearching { get => searching; private set { searching = value; Notify(); } }
    public ObservableCollection<RoomSearchRoomResult> RoomResults { get; } = [];
    public ObservableCollection<RoomSearchUserResult> UserResults { get; } = [];
    public async Task SearchAsync(CancellationToken token = default)
    {
        if (disposed) return;
        var request = ++generation;
        activeSearch?.Cancel();
        using var source = CancellationTokenSource.CreateLinkedTokenSource(token);
        activeSearch = source;
        var prefix = SearchableText.Normalize(Query);
        Error = "";
        if (prefix.Length == 0) { RoomResults.Clear(); UserResults.Clear(); IsSearching = false; activeSearch = null; return; }
        var uid = currentUid();
        IsSearching = true;
        try
        {
            var rooms = roomService.SearchOpenRoomsAsync(prefix, source.Token);
            var users = userService.SearchByNicknamePrefixAsync(prefix, source.Token);
            await Task.WhenAll(rooms, users);
            if (disposed || request != generation || source.IsCancellationRequested || uid != currentUid()) return;
            var joined = myRooms().Select(room => room.Id).Where(id => id is not null).ToHashSet(StringComparer.Ordinal);
            RoomResults.Clear(); UserResults.Clear();
            foreach (var room in await rooms)
                RoomResults.Add(new(room, uid is not null && !room.MemberUids.Contains(uid) && !joined.Contains(room.Id)));
            foreach (var user in await users)
                if (user.Id is { Length: > 0 } && user.Id != uid)
                    UserResults.Add(new(user, uid is not null && !user.Rooms.Any(joined.Contains)));
        }
        catch (OperationCanceledException) when (source.IsCancellationRequested) { }
        catch (Exception ex)
        {
            if (!disposed && request == generation && !source.IsCancellationRequested)
            { RoomResults.Clear(); UserResults.Clear(); Error = ex.Message; }
        }
        finally
        {
            if (!disposed && request == generation) IsSearching = false;
            if (ReferenceEquals(activeSearch, source)) activeSearch = null;
        }
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; generation++; activeSearch?.Cancel(); IsSearching = false;
    }
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
