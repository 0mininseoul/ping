using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;

namespace Ping.Windows.App.Setup;

public sealed record EmailAccountActions(
    Func<CancellationToken, Task<EmailAccountStatus>> ReadStatus,
    Func<string, string, CancellationToken, Task> RequestLink,
    Func<string, CancellationToken, Task> RequestSignIn,
    Func<string, string, EmailAuthenticationPurpose, string?, CancellationToken, Task<EmailAuthenticationResult>> Verify,
    Func<EmailAuthenticationResult, Task> Accept,
    Func<EmailAuthenticationResult?> Pending);

public sealed class EmailAccountViewModel : INotifyPropertyChanged, IDisposable
{
    private readonly EmailAccountActions? actions;
    private readonly CancellationTokenSource lifetime = new();
    private string email = "", code = "", status = "이메일을 연결하면 다른 PC에서도 같은 계정을 쓸 수 있어요.";
    private string linkedEmail = "이메일 연결 상태를 확인하고 있어요…";
    private string? currentUserId, requestedEmail, linkingUserId;
    private EmailAuthenticationPurpose purpose;
    private EmailAuthenticationResult? verified;
    private DateTimeOffset nextRequest;
    private bool confirmed, busy, disposed;

    public EmailAccountViewModel(EmailAccountActions? actions = null)
    {
        this.actions = actions;
        verified = actions?.Pending();
        if (verified is not null)
        {
            email = verified.Email;
            status = "이메일 인증은 완료됐어요. ‘로그인 완료’를 눌러 계정 저장을 다시 시도해 주세요.";
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public string Email { get => email; set { email = value; Notify(); NotifyActions(); } }
    public string Code { get => code; set { code = value; Notify(); NotifyActions(); } }
    public string Status { get => status; private set { status = value; Notify(); } }
    public string LinkedEmail { get => linkedEmail; private set { linkedEmail = value; Notify(); } }
    public bool IsBusy { get => busy; private set { busy = value; Notify(); NotifyActions(); } }
    public bool HasPendingFlow => requestedEmail is not null || verified is not null;
    public bool CanEditEmail => !IsBusy && !HasPendingFlow;
    public bool CanEditCode => !IsBusy && requestedEmail is not null && verified is null;
    public bool CanLink => CanRequest && currentUserId is not null && !confirmed;
    public bool CanSignIn => CanRequest;
    public bool CanResend => !IsBusy && requestedEmail is not null && verified is null && DateTimeOffset.UtcNow >= nextRequest;
    public bool CanReset => !IsBusy && requestedEmail is not null && verified is null;
    public bool CanVerify => !IsBusy && (verified is not null || requestedEmail is not null && ValidCode());
    public string CompleteButtonText => verified is not null ? "로그인 완료"
        : purpose == EmailAuthenticationPurpose.LinkCurrentAccount ? "이메일 연결 완료" : "로그인 완료";
    private bool CanRequest => actions is not null && CanEditEmail && ValidEmail() && DateTimeOffset.UtcNow >= nextRequest;

    public async Task RefreshAsync()
    {
        if (disposed || IsBusy || actions is null) return;
        IsBusy = true;
        try
        {
            var account = await actions.ReadStatus(lifetime.Token);
            currentUserId = account.UserId;
            confirmed = account.IsConfirmed && !string.IsNullOrWhiteSpace(account.Email);
            LinkedEmail = confirmed ? $"{account.Email} · 연결됨" : "아직 이메일이 연결되지 않았어요.";
            if (confirmed && string.IsNullOrWhiteSpace(Email) && !HasPendingFlow) Email = account.Email!;
        }
        catch (Exception error)
        {
            currentUserId = null;
            LinkedEmail = "현재 계정의 이메일 연결 상태를 확인하지 못했어요.";
            if (!HasPendingFlow) Status = EmailAccountError.Message(error) + " 연결했던 이메일로 로그인할 수 있습니다.";
        }
        finally { IsBusy = false; }
    }

    public Task LinkAsync() => CanLink ? RequestAsync(EmailAuthenticationPurpose.LinkCurrentAccount, false) : Task.CompletedTask;
    public Task SignInAsync() => CanSignIn ? RequestAsync(EmailAuthenticationPurpose.SignIn, false) : Task.CompletedTask;
    public Task ResendAsync() => CanResend ? RequestAsync(purpose, true) : Task.CompletedTask;

    private async Task RequestAsync(EmailAuthenticationPurpose requestedPurpose, bool resend)
    {
        if (disposed || actions is null || IsBusy) return;
        IsBusy = true;
        try
        {
            var address = resend ? requestedEmail! : EmailAccountInput.Normalize(Email);
            var uid = resend ? linkingUserId : currentUserId;
            if (requestedPurpose == EmailAuthenticationPurpose.LinkCurrentAccount)
                await actions.RequestLink(address, uid ?? throw new SupabaseAccountRequiredException(), lifetime.Token);
            else await actions.RequestSignIn(address, lifetime.Token);
            purpose = requestedPurpose; requestedEmail = address; linkingUserId = uid;
            Email = address; Code = "";
            Status = $"{address}로 요청했어요. 메일의 인증번호를 입력해 주세요. 메일이 없다면 스팸함과 이메일 연결 여부를 확인해 주세요.";
            DelayNextRequest(TimeSpan.FromSeconds(60));
        }
        catch (Exception error)
        {
            Status = EmailAccountError.Message(error);
            if (error is SupabaseRequestException { RetryAfter: { } delay }) DelayNextRequest(delay);
        }
        finally { IsBusy = false; }
    }

    public async Task CompleteAsync()
    {
        if (disposed || actions is null || !CanVerify) return;
        IsBusy = true;
        try
        {
            verified ??= await actions.Verify(requestedEmail!, Code, purpose, linkingUserId, lifetime.Token);
            Code = "";
            Status = "인증을 확인했어요. 계정과 대화방을 불러오고 있어요…";
            await actions.Accept(verified);
            verified = null; requestedEmail = null; linkingUserId = null;
            Status = "이메일 계정으로 연결했어요.";
        }
        catch (Exception error) { Status = EmailAccountError.Message(error); }
        finally { IsBusy = false; }
    }

    public void Reset()
    {
        if (!CanReset) return;
        requestedEmail = null; linkingUserId = null; Code = "";
        Status = "현재 계정은 유지됩니다. 이메일 주소를 입력해 다시 요청해 주세요.";
        NotifyActions();
    }

    private void DelayNextRequest(TimeSpan delay)
    {
        nextRequest = DateTimeOffset.UtcNow.Add(delay < TimeSpan.Zero ? TimeSpan.Zero : delay);
        _ = ReleaseCooldownAsync(nextRequest);
        NotifyActions();
    }
    private async Task ReleaseCooldownAsync(DateTimeOffset deadline)
    {
        try
        {
            var delay = deadline - DateTimeOffset.UtcNow;
            if (delay > TimeSpan.Zero) await Task.Delay(delay, lifetime.Token);
            NotifyActions();
        }
        catch (OperationCanceledException) { }
    }
    private bool ValidEmail() { try { _ = EmailAccountInput.Normalize(Email); return true; } catch (ArgumentException) { return false; } }
    private bool ValidCode() { try { _ = EmailAccountInput.Code(Code); return true; } catch (ArgumentException) { return false; } }
    private void NotifyActions()
    {
        foreach (var name in new[] { nameof(HasPendingFlow), nameof(CanEditEmail), nameof(CanEditCode), nameof(CanLink),
            nameof(CanSignIn), nameof(CanResend), nameof(CanReset), nameof(CanVerify), nameof(CompleteButtonText) }) Notify(name);
    }
    private void Notify([CallerMemberName] string? name = null) { if (!disposed) PropertyChanged?.Invoke(this, new(name)); }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; code = ""; lifetime.Cancel(); lifetime.Dispose();
    }
}
