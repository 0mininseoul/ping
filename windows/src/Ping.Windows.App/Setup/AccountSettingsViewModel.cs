using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;

namespace Ping.Windows.App.Setup;

public enum AccountChangeKind { Create, Switch, Remove }
public sealed record AccountChange(AccountChangeKind Kind, string? UserId = null);
public sealed record AccountSettingRow(string UserId, string Label, bool IsActive);

public sealed class AccountSettingsViewModel(
    Func<CancellationToken, Task<IReadOnlyList<StoredAccountSummary>>> load,
    Func<AccountChange, CancellationToken, Task> change) : INotifyPropertyChanged
{
    private bool busy;
    private string status = "저장 계정을 확인하고 있어요…";
    private AccountSettingRow? selected;
    private string? transitionFailure;
    public void ReportTransitionFailure()
    {
        transitionFailure = "계정 변경을 완료하지 못했어요. 저장된 계정을 확인하고 다시 시도해 주세요.";
        Status = transitionFailure;
    }
    public event PropertyChangedEventHandler? PropertyChanged;
    public ObservableCollection<AccountSettingRow> Accounts { get; } = [];
    public string Status { get => status; private set { status = value; Notify(); } }
    public bool IsBusy { get => busy; private set { busy = value; Notify(); NotifyActions(); } }
    public bool CanCreate => !IsBusy;
    public bool CanSwitch => CanCreate && SelectedAccount is { IsActive: false };
    public bool CanRemove => CanCreate && SelectedAccount is not null;
    public AccountSettingRow? SelectedAccount
    {
        get => selected;
        set { selected = value; Notify(); NotifyActions(); }
    }
    public Task RefreshAsync(CancellationToken token = default) => RunAsync(null, token);
    public Task CreateAsync(CancellationToken token = default) => CanCreate ? RunAsync(new(AccountChangeKind.Create), token) : Task.CompletedTask;
    public Task SwitchAsync(CancellationToken token = default) => CanSwitch
        ? RunAsync(new(AccountChangeKind.Switch, SelectedAccount!.UserId), token) : Task.CompletedTask;
    public Task RemoveAsync(CancellationToken token = default) => CanRemove
        ? RunAsync(new(AccountChangeKind.Remove, SelectedAccount!.UserId), token) : Task.CompletedTask;

    private async Task RunAsync(AccountChange? request, CancellationToken token)
    {
        if (IsBusy) return;
        IsBusy = true;
        try
        {
            if (request is not null)
            {
                transitionFailure = null;
                Status = "계정을 변경하고 있어요…";
                await change(request, token);
            }
            var accounts = await load(token);
            Accounts.Clear();
            foreach (var row in accounts)
            {
                var name = string.IsNullOrWhiteSpace(row.Nickname) ? "새 계정" : row.Nickname;
                var id = row.UserId[..Math.Min(row.UserId.Length, 8)];
                Accounts.Add(new(row.UserId, $"{name} · {id}{(row.IsActive ? " · 사용 중" : "")}", row.IsActive));
            }
            SelectedAccount = Accounts.FirstOrDefault(row => row.IsActive) ?? Accounts.FirstOrDefault();
            Status = transitionFailure ?? (Accounts.Count == 0 ? "저장된 계정이 없습니다. 새 계정을 추가해 주세요." : "계정을 바꾸면 해당 계정의 룸과 메시지를 불러옵니다.");
        }
        catch (OperationCanceledException) { Status = "계정 변경을 취소했어요."; }
        catch (Exception) { Status = "계정을 변경하거나 불러오지 못했어요. 다시 시도해 주세요."; }
        finally { IsBusy = false; }
    }
    private void NotifyActions() { Notify(nameof(CanCreate)); Notify(nameof(CanSwitch)); Notify(nameof(CanRemove)); }
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
