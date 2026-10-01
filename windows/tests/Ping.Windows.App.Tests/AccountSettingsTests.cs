using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class AccountSettingsTests
{
    [Fact]
    public async Task LoadsActiveAccountAndSwitchesOnlyExplicitSelection()
    {
        IReadOnlyList<StoredAccountSummary> stored = [new("first", "첫 계정", DateTimeOffset.UtcNow, true), new("second", "둘째", DateTimeOffset.UtcNow, false)];
        AccountChange? change = null;
        var model = new AccountSettingsViewModel(_ => Task.FromResult(stored), (value, _) =>
        {
            change = value; stored = stored.Select(row => row with { IsActive = row.UserId == value.UserId }).ToArray();
            return Task.CompletedTask;
        });
        await model.RefreshAsync();
        Assert.Equal("first", model.SelectedAccount!.UserId); Assert.False(model.CanSwitch);
        model.SelectedAccount = model.Accounts.Single(row => row.UserId == "second");
        Assert.True(model.CanSwitch); await model.SwitchAsync();
        Assert.Equal(new AccountChange(AccountChangeKind.Switch, "second"), change);
        Assert.Equal("second", model.Accounts.Single(row => row.IsActive).UserId);
    }

    [Fact]
    public async Task FailureKeepsAccountsAndDoesNotExposeExceptionDetailsOrCreateReplacement()
    {
        var model = new AccountSettingsViewModel(_ => Task.FromResult<IReadOnlyList<StoredAccountSummary>>([new("first", "", DateTimeOffset.UtcNow, true)]),
            (_, _) => throw new IOException("secret-access-token"));
        await model.RefreshAsync(); await model.CreateAsync();
        Assert.Single(model.Accounts); Assert.Equal("first", model.SelectedAccount!.UserId);
        Assert.DoesNotContain("secret", model.Status); Assert.Contains("다시", model.Status); Assert.True(model.CanCreate);
    }

    [Fact]
    public async Task PendingTransitionDisablesDuplicateCommands()
    {
        var pending = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); var calls = 0;
        var model = new AccountSettingsViewModel(_ => Task.FromResult<IReadOnlyList<StoredAccountSummary>>([]), (_, _) => { calls++; return pending.Task; });
        await model.RefreshAsync(); Assert.Contains("새 계정", model.Status);
        var creating = model.CreateAsync(); Assert.False(model.CanCreate);
        await model.CreateAsync(); Assert.Equal(1, calls);
        pending.SetResult(); await creating; Assert.True(model.CanCreate);
    }
}
