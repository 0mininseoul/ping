using Ping.Windows.App.Onboarding;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class GuidedSetupTests
{
    [Fact]
    public async Task Missing_camera_does_not_block_profile_and_messenger_setup()
    {
        using var model = Model();
        await model.NextAsync();
        Assert.Equal(GuidedSetupStep.Permissions, model.Step);
        await model.NextAsync();
        Assert.Equal(GuidedSetupStep.Nickname, model.Step);
        model.Nickname = "  민지  ";
        await model.NextAsync();
        Assert.Equal(GuidedSetupStep.ConnectionChoice, model.Step);
        model.StartLater();
        Assert.Equal(GuidedSetupStep.Done, model.Step);
    }

    [Fact]
    public async Task Failed_profile_save_preserves_draft_and_never_creates_room()
    {
        var creates = 0;
        using var model = Model(save: (_, _) => throw new IOException(), create: (_, _, _) => { creates++; return Task.CompletedTask; });
        await model.NextAsync(); await model.NextAsync(); model.Nickname = "민지";
        await model.NextAsync();
        Assert.Equal(GuidedSetupStep.Nickname, model.Step);
        Assert.Equal("민지", model.Nickname);
        Assert.False(string.IsNullOrWhiteSpace(model.Error));
        Assert.Equal(0, creates);
    }

    [Fact]
    public async Task Repeated_submit_during_save_does_not_write_twice_or_navigate_back()
    {
        var pending = new TaskCompletionSource<string>(); var saves = 0;
        using var model = Model(save: (_, _) => { saves++; return pending.Task; });
        await model.NextAsync(); await model.NextAsync(); model.Nickname = "민지";
        var saving = model.NextAsync();
        await model.NextAsync(); model.Back();
        Assert.True(model.IsBusy); Assert.Equal(1, saves); Assert.Equal(GuidedSetupStep.Nickname, model.Step);
        pending.SetResult("민지"); await saving;
        Assert.Equal(GuidedSetupStep.ConnectionChoice, model.Step);
    }

    [Theory]
    [InlineData("")]
    [InlineData("    ")]
    [InlineData("1234567890123456789012345")]
    public async Task Invalid_nickname_never_saves(string nickname)
    {
        var saves = 0;
        using var model = Model(save: (_, _) => { saves++; return Task.FromResult("bad"); });
        await model.NextAsync(); await model.NextAsync(); model.Nickname = nickname;
        await model.NextAsync();
        Assert.Equal(0, saves); Assert.Equal(GuidedSetupStep.Nickname, model.Step); Assert.False(model.CanContinue);
    }

    [Fact]
    public async Task Successful_create_is_not_repeated_after_completion()
    {
        var creates = 0; string? sentName = null;
        using var model = Model(create: (name, nickname, _) => { creates++; sentName = name; Assert.Equal("민지", nickname); return Task.CompletedTask; });
        await ProfileAsync(model); model.ChooseCreateRoom(); model.RoomName = "  친구와   나  ";
        await model.NextAsync(); await model.NextAsync();
        Assert.Equal(1, creates); Assert.Equal("친구와 나", sentName); Assert.Equal(GuidedSetupStep.Done, model.Step);
    }

    [Fact]
    public void Room_name_cap_matches_Mac_without_splitting_an_emoji()
    {
        using var model = Model();
        model.RoomName = new string('가', 15) + "😀" + "끝";
        Assert.Equal(new string('가', 15) + "😀", model.RoomName);
        Assert.Equal("16/16", model.RoomNameCount);
    }

    [Fact]
    public async Task Room_search_excludes_own_full_and_already_joined_rooms()
    {
        using var model = Model(search: (_, _) => Task.FromResult<IReadOnlyList<Room>>([
            Room("open", "other", ["other"], RoomStatus.Open), Room("own", "me", ["me"], RoomStatus.Open),
            Room("full", "other", ["other", "third"], RoomStatus.Full), Room("member", "other", ["other", "me"], RoomStatus.Open)]));
        await ProfileAsync(model); model.ChooseJoinRoom(); model.SearchText = "친구"; await model.SearchAsync();
        Assert.Equal("open", Assert.Single(model.SearchResults).Id);
        model.SearchText = " "; await model.SearchAsync(); Assert.Empty(model.SearchResults);
    }

    [Fact]
    public async Task Failed_join_keeps_selection_for_retry_and_does_not_complete()
    {
        using var model = Model(join: (_, _, _) => throw new IOException());
        await ProfileAsync(model); model.ChooseJoinRoom(); model.SearchText = "친구"; await model.SearchAsync();
        model.SelectedRoom = Assert.Single(model.SearchResults); await model.NextAsync();
        Assert.Equal(GuidedSetupStep.JoinRoom, model.Step); Assert.NotNull(model.SelectedRoom); Assert.NotEmpty(model.Error);
    }

    [Fact]
    public async Task Closing_during_save_cancels_callback_and_cannot_advance()
    {
        CancellationToken operationToken = default;
        var pending = new TaskCompletionSource<string>();
        var model = Model(save: (_, token) => { operationToken = token; return pending.Task; });
        await model.NextAsync(); await model.NextAsync(); model.Nickname = "민지";
        var saving = model.NextAsync(); model.Dispose(); pending.SetResult("민지"); await saving;
        Assert.True(operationToken.IsCancellationRequested); Assert.Equal(GuidedSetupStep.Nickname, model.Step);
    }

    private static async Task ProfileAsync(GuidedSetupViewModel model)
    {
        await model.NextAsync(); await model.NextAsync(); model.Nickname = "민지"; await model.NextAsync();
    }
    private static Room Room(string id, string owner, IReadOnlyList<string> members, RoomStatus status) =>
        new(id, "친구", "친구", owner, members, new Dictionary<string, string>(), status);
    private static GuidedSetupViewModel Model(
        Func<string, CancellationToken, Task<string>>? save = null,
        Func<string, string, CancellationToken, Task>? create = null,
        Func<string, CancellationToken, Task<IReadOnlyList<Room>>>? search = null,
        Func<string, string, CancellationToken, Task>? join = null) => new(new(
            save ?? ((name, _) => Task.FromResult(name)), create ?? ((_, _, _) => Task.CompletedTask),
            search ?? ((_, _) => Task.FromResult<IReadOnlyList<Room>>([Room("open", "other", ["other"], RoomStatus.Open)])),
            join ?? ((_, _, _) => Task.CompletedTask), () => "me"));
}
