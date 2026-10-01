using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Updates;

namespace Ping.Windows.App.Setup;

public sealed class UpdateSettingsViewModel(string currentVersion,
    Func<CancellationToken, Task<WindowsUpdateCandidate?>> check,
    Func<WindowsUpdateCandidate, IProgress<UpdateDownloadProgress>, CancellationToken, Task> install,
    Action? dispose = null) : INotifyPropertyChanged, IDisposable
{
    private CancellationTokenSource? operation;
    private WindowsUpdateCandidate? candidate;
    private bool disposed;
    private string status = "업데이트 확인을 눌러 최신 Windows 버전을 확인하세요.";
    public event PropertyChangedEventHandler? PropertyChanged;
    public string CurrentVersion { get; } = currentVersion;
    public string Status { get => status; private set { status = value; Notify(); } }
    public bool IsBusy => operation is not null;
    public bool CanCheck => !disposed && !IsBusy;
    public bool CanInstall => CanCheck && candidate is not null;
    public bool CanCancel => !disposed && IsBusy;
    public Task CheckAsync() => RunAsync(false);
    public Task InstallAsync() => CanInstall ? RunAsync(true) : Task.CompletedTask;
    public void Cancel() => operation?.Cancel();
    public void ReportFailure() => Status = "업데이트를 적용하지 못했어요. 기존 버전을 유지합니다. 다시 확인해 주세요.";

    private async Task RunAsync(bool applying)
    {
        if (!CanCheck) return;
        using var cancellation = new CancellationTokenSource(applying ? TimeSpan.FromMinutes(15) : TimeSpan.FromSeconds(30));
        operation = cancellation; NotifyActions();
        try
        {
            if (applying)
            {
                Status = "업데이트를 내려받고 확인하고 있어요…";
                var progress = new Progress<UpdateDownloadProgress>(value =>
                {
                    if (!disposed && ReferenceEquals(operation, cancellation) && !cancellation.IsCancellationRequested)
                        Status = value.TotalBytes is > 0 ? $"내려받는 중… {Math.Min(100, value.Bytes * 100 / value.TotalBytes.Value)}%" : "내려받는 중…";
                });
                await install(candidate!, progress, cancellation.Token);
                Status = "업데이트를 준비했어요. Ping을 다시 시작합니다.";
            }
            else
            {
                candidate = null; Status = "최신 버전을 확인하고 있어요…";
                candidate = await check(cancellation.Token);
                Status = candidate is null ? "최신 버전을 사용하고 있어요." : $"Windows {candidate.Version.ToString(3)} 업데이트가 있어요.";
            }
        }
        catch (OperationCanceledException) { Status = "업데이트 작업을 취소했어요. 다시 시도할 수 있습니다."; }
        catch (Exception) { ReportFailure(); }
        finally { operation = null; NotifyActions(); }
    }
    public void Dispose() { if (disposed) return; disposed = true; Cancel(); dispose?.Invoke(); }
    private void NotifyActions() { Notify(nameof(IsBusy)); Notify(nameof(CanCheck)); Notify(nameof(CanInstall)); Notify(nameof(CanCancel)); }
    private void Notify([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
}
