using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;

namespace Ping.Windows.App.Setup;

public sealed class AccountKeySettingsViewModel(
    Func<CancellationToken, Task<bool>> load,
    Func<string, CancellationToken, Task> save) : INotifyPropertyChanged
{
    private bool busy, enabled;
    private string status = "다른 PC에서도 쓰고 싶을 때만 비밀키를 정하세요.";
    public event PropertyChangedEventHandler? PropertyChanged;
    public string Status { get => status; private set { status = value; Notify(); } }
    public bool IsBusy { get => busy; private set { busy = value; Notify(); Notify(nameof(CanEdit)); } }
    public bool CanEdit => !IsBusy;
    public string SetKeyLabel => enabled ? "비밀키 변경" : "비밀키 만들기";

    public async Task RefreshAsync(CancellationToken token)
    {
        if (IsBusy) return;
        IsBusy = true;
        try
        {
            enabled = await load(token);
            Status = enabled ? "비밀키가 설정되어 있어요. 다른 PC에서 현재 닉네임과 키를 입력하세요." : "필요한 경우에만 비밀키를 만들면 돼요.";
            Notify(nameof(SetKeyLabel));
        }
        catch (OperationCanceledException) { }
        catch (AccountKeyException ex) { Status = ex.Message; }
        catch { Status = "계정 연결 상태를 불러오지 못했어요. 연결을 확인해 주세요."; }
        finally { IsBusy = false; }
    }

    public async Task SaveAsync(string key, CancellationToken token)
    {
        if (IsBusy) throw new AccountKeyException("진행 중인 작업이 끝나면 다시 시도해 주세요.");
        IsBusy = true;
        try
        {
            await save(key, token);
            enabled = true; Notify(nameof(SetKeyLabel));
            Status = "비밀키를 저장했어요. 현재 닉네임과 키로 다른 PC에서도 이어 쓸 수 있어요.";
        }
        finally { IsBusy = false; }
    }
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
