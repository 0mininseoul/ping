using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Ping.Windows.App.Setup;

public sealed class DevicePairingViewModel(Func<CancellationToken, Task<PairingQrImage>> generate, Func<string?> currentUid)
    : INotifyPropertyChanged
{
    private CancellationTokenSource? request;
    private long epoch;
    private PairingQrImage? image;
    private bool isActive, isLoading;
    private string status = "기기 탭을 열면 연결 QR을 준비합니다.";
    public event PropertyChangedEventHandler? PropertyChanged;
    public PairingQrImage? Image { get => image; private set { image = value; Notify(); } }
    public bool IsActive { get => isActive; private set { isActive = value; Notify(); } }
    public bool IsLoading { get => isLoading; private set { isLoading = value; Notify(); Notify(nameof(CanRetry)); } }
    public bool CanRetry => !IsLoading;
    public string Status { get => status; private set { status = value; Notify(); } }

    public async Task OpenAsync()
    {
        Deactivate(); IsActive = true; IsLoading = true; Status = "연결 QR을 준비하고 있어요…";
        var generation = epoch;
        request = new(); request.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            var result = await generate(request.Token);
            if (!IsActive || generation != epoch) return;
            if (result.UserId != currentUid()) { Status = "계정이 변경되었어요. QR을 다시 준비해 주세요."; return; }
            if (result.ExpiresAt <= DateTimeOffset.UtcNow) { Status = "세션이 만료되었어요. QR을 다시 준비해 주세요."; return; }
            Image = result; Status = "iPhone의 Ping 앱에서 스캔하면 같은 계정으로 연결됩니다.";
        }
        catch (OperationCanceledException)
        {
            if (IsActive && generation == epoch) Status = "QR 준비를 마치지 못했어요. 다시 시도해 주세요.";
        }
        catch (Exception)
        {
            if (IsActive && generation == epoch) Status = "세션을 준비하지 못했어요. 연결 상태를 확인하고 다시 시도해 주세요.";
        }
        finally { if (generation == epoch) IsLoading = false; }
    }
    public void Deactivate()
    {
        epoch++; request?.Cancel(); request?.Dispose(); request = null;
        Image = null; IsActive = false; IsLoading = false;
    }
    public void ReportRenderingFailure()
    {
        Deactivate(); Status = "QR을 표시하지 못했어요. 다시 시도해 주세요.";
    }
    private void Notify([CallerMemberName] string? property = null) => PropertyChanged?.Invoke(this, new(property));
}
