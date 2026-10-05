using System.Net;
using System.Net.Mail;

namespace Ping.Windows.Core.Backend;

public enum EmailAuthenticationPurpose { LinkCurrentAccount, SignIn }
public sealed record EmailAccountStatus(string UserId, string? Email, bool IsConfirmed);

public sealed class EmailAuthenticationResult
{
    internal EmailAuthenticationResult(SupabaseSession session, Uri projectUrl, string email)
        => (Session, ProjectUrl, Email) = (session, projectUrl, email);
    internal SupabaseSession Session { get; private set; }
    internal Uri ProjectUrl { get; }
    public string UserId => Session.UserId;
    public string Email { get; }
    internal void RetainRefreshedSession(SupabaseSession refreshed)
    {
        if (refreshed.UserId != UserId) throw new InvalidOperationException("Email session identity changed.");
        Session = refreshed;
    }
    public override string ToString() => "Verified Ping email account (credentials redacted)";
}

public static class EmailAccountInput
{
    public static string Normalize(string email)
    {
        var value = email.Trim();
        if (value.Length > 254 || !MailAddress.TryCreate(value, out var address)
            || !string.Equals(address.Address, value, StringComparison.OrdinalIgnoreCase)
            || !address.Host.Contains('.'))
            throw new ArgumentException("이메일 주소를 확인해 주세요.");
        return value.ToLowerInvariant();
    }

    public static string Code(string code)
    {
        var value = code.Trim();
        if (value.Length is < 6 or > 10 || value.Any(c => c is < '0' or > '9'))
            throw new ArgumentException("메일에 표시된 숫자 인증번호를 입력해 주세요.");
        return value;
    }
}

public static class EmailAccountError
{
    public static string Message(Exception error) => error switch
    {
        SupabaseRequestException { ErrorCode: "email_exists" or "user_already_exists" or "identity_already_exists" } =>
            "이미 다른 계정에 연결된 이메일입니다. 그 계정을 쓰려면 ‘기존 계정 로그인’을 선택해 주세요.",
        SupabaseRequestException { ErrorCode: "otp_expired" } => "인증번호가 만료됐거나 일치하지 않아요. 번호를 다시 요청해 주세요.",
        SupabaseRequestException { ErrorCode: "email_address_not_authorized" } =>
            "현재 메일 발송 설정으로는 이 주소에 인증번호를 보낼 수 없어요. Ping 운영자의 SMTP 설정이 필요합니다.",
        SupabaseRequestException { ErrorCode: "email_provider_disabled" or "manual_linking_disabled" or "otp_disabled" } =>
            "이메일 인증 설정이 아직 준비되지 않았어요. Ping 운영자가 이메일 로그인 설정을 활성화해야 합니다.",
        SupabaseRequestException { ErrorCode: "email_address_invalid" or "validation_failed" } =>
            "이메일 주소와 인증번호를 확인해 주세요.",
        SupabaseRequestException { StatusCode: HttpStatusCode.TooManyRequests } =>
            "인증 요청이 너무 많아요. 잠시 기다린 뒤 다시 요청해 주세요.",
        SupabaseSessionExpiredException => "현재 계정 인증이 만료됐어요. 연결했던 이메일로 다시 로그인해 주세요.",
        SupabaseSessionReadException => "저장된 계정 파일을 읽지 못했어요. 파일을 보존한 채 복구가 필요합니다.",
        IOException or UnauthorizedAccessException => "계정 정보를 저장하지 못했어요. 인증이 완료됐다면 ‘로그인 완료’를 다시 눌러 주세요.",
        ArgumentException => "이메일 주소와 메일의 숫자 인증번호를 확인해 주세요.",
        OperationCanceledException => "요청이 취소되었거나 연결 시간이 초과됐어요. 다시 시도해 주세요.",
        HttpRequestException => "인증 요청을 완료하지 못했어요. 인터넷 연결과 메일 발송 설정을 확인해 주세요.",
        _ => "이메일 인증을 완료하지 못했어요. 현재 계정은 유지됩니다. 다시 시도해 주세요."
    };
}
