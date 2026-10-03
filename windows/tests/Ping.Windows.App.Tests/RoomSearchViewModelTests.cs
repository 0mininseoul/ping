using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class RoomSearchViewModelTests
{
    [Fact]
    public async Task SearchNormalizesQueryFiltersSelfAndMarksExistingConnections()
    {
        var rpc = new SearchRpc
        {
            Rooms = (_, _) => Task.FromResult<IReadOnlyList<Room>>([Room("mine", "같은 이름", ["me"]), Room("other", "같은 이름", ["owner"])]),
            Users = (_, _) => Task.FromResult<IReadOnlyList<PingUser>>([User("me", []), User("shared", ["mine"]), User("new", [])])
        };
        using var model = Model(rpc);
        model.Query = "  HELLO\tPing  ";
        await model.SearchAsync();
        Assert.All(rpc.Queries, query => Assert.Equal("hello ping", query));
        Assert.Equal(2, model.RoomResults.Count);
        Assert.False(model.RoomResults[0].CanJoin);
        Assert.True(model.RoomResults[1].CanJoin);
        Assert.Equal("방장: 방장 이름", model.RoomResults[1].OwnerNicknameLabel);
        Assert.Equal(["shared", "new"], model.UserResults.Select(row => row.User.Id));
        Assert.False(model.UserResults[0].CanInvite);
        Assert.True(model.UserResults[1].CanInvite);
        Assert.False(model.IsSearching);
        Assert.Empty(model.Error);
    }

    [Fact]
    public async Task LatePreviousSearchCannotReplaceNewerResults()
    {
        var delayed = new TaskCompletionSource<IReadOnlyList<Room>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var rpc = new SearchRpc { Rooms = (query, _) => query == "old" ? delayed.Task : Task.FromResult<IReadOnlyList<Room>>([Room("new", "새 결과", [])]) };
        using var model = Model(rpc);
        model.Query = "old";
        var oldSearch = model.SearchAsync();
        model.Query = "new";
        await model.SearchAsync();
        delayed.SetResult([Room("old", "오래된 결과", [])]);
        await oldSearch;
        Assert.Equal("new", Assert.Single(model.RoomResults).Room.Id);
        Assert.False(model.IsSearching);
    }

    [Fact]
    public async Task ClearingQueryDuringRequestLeavesNoResultsOrError()
    {
        var delayed = new TaskCompletionSource<IReadOnlyList<Room>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var rpc = new SearchRpc { Rooms = (_, _) => delayed.Task };
        using var model = Model(rpc);
        model.Query = "old";
        var search = model.SearchAsync();
        Assert.True(model.IsSearching);
        model.Query = " ";
        await model.SearchAsync();
        delayed.SetException(new InvalidOperationException("오래된 오류"));
        await search;
        Assert.Empty(model.RoomResults);
        Assert.Empty(model.UserResults);
        Assert.Empty(model.Error);
        Assert.False(model.IsSearching);
    }

    [Fact]
    public async Task FailedSearchKeepsQueryAndAllowsRetry()
    {
        var rpc = new SearchRpc { Rooms = (_, _) => Task.FromException<IReadOnlyList<Room>>(new InvalidOperationException("연결 실패")) };
        using var model = Model(rpc);
        model.Query = "기억할 검색어";
        await model.SearchAsync();
        Assert.Equal("기억할 검색어", model.Query);
        Assert.Contains("연결 실패", model.Error);
        rpc.Rooms = (_, _) => Task.FromResult<IReadOnlyList<Room>>([Room("found", "다시 검색", [])]);
        await model.SearchAsync();
        Assert.Equal("found", Assert.Single(model.RoomResults).Room.Id);
        Assert.Empty(model.Error);
    }

    [Fact]
    public async Task DisposedSearchCannotApplyLateResults()
    {
        var delayed = new TaskCompletionSource<IReadOnlyList<Room>>(TaskCreationOptions.RunContinuationsAsynchronously);
        var model = Model(new SearchRpc { Rooms = (_, _) => delayed.Task });
        model.Query = "old";
        var search = model.SearchAsync();
        Assert.True(model.IsSearching);
        model.Dispose();
        delayed.SetResult([Room("late", "늦은 결과", [])]);
        await search;
        Assert.Empty(model.RoomResults);
        Assert.False(model.IsSearching);
    }

    private static RoomSearchViewModel Model(SearchRpc rpc) => new(new RoomService(rpc), new UserService(rpc), () => "me", () => [Room("mine", "내 룸", ["me"])]);
    private static Room Room(string id, string name, IReadOnlyList<string> members) => new(id, name, name, "owner", members, new Dictionary<string, string> { ["owner"] = "방장 이름" }, RoomStatus.Open);
    private static PingUser User(string id, IReadOnlyList<string> rooms) => new(id, id, id, rooms, null);

    private sealed class SearchRpc : ISupabaseRpcClient
    {
        public Func<string, CancellationToken, Task<IReadOnlyList<Room>>> Rooms { get; set; } = (_, _) => Task.FromResult<IReadOnlyList<Room>>([]);
        public Func<string, CancellationToken, Task<IReadOnlyList<PingUser>>> Users { get; set; } = (_, _) => Task.FromResult<IReadOnlyList<PingUser>>([]);
        public List<string> Queries { get; } = [];
        public async Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function == "ping_search_open_rooms" && body is SearchOpenRoomsRpcBody roomBody)
            { Queries.Add(roomBody.SearchPrefix); return (IReadOnlyList<T>)(object)await Rooms(roomBody.SearchPrefix, cancellationToken); }
            if (function == "ping_search_profiles" && body is SearchProfilesRpcBody userBody)
            { Queries.Add(userBody.SearchPrefix); return (IReadOnlyList<T>)(object)await Users(userBody.SearchPrefix, cancellationToken); }
            throw new NotSupportedException(function);
        }
        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default) => throw new NotSupportedException();
    }
}
