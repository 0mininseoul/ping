using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Backend;

public sealed record StoredAccountSummary(string UserId, string Nickname, DateTimeOffset AddedAt, bool IsActive);
public sealed class SupabaseAccountRequiredException() : InvalidOperationException("저장된 계정이 없습니다. 새 계정을 명시적으로 추가해 주세요.");

internal sealed record SavedSupabaseAccount(
    [property: JsonPropertyName("session")] SupabaseSession Session,
    [property: JsonPropertyName("nickname")] string Nickname,
    [property: JsonPropertyName("added_at")] DateTimeOffset AddedAt)
{
    public override string ToString() => "Saved Ping account (session redacted)";
}

internal sealed record SupabaseAccountsState(IReadOnlyList<SavedSupabaseAccount> Accounts, string? ActiveUserId, bool Initialized = true)
{
    internal SupabaseSession? ActiveSession => Accounts.FirstOrDefault(row => row.Session.UserId == ActiveUserId)?.Session;
    internal SupabaseAccountsState Upsert(SupabaseSession session, bool activate = false)
    {
        var existing = Accounts.FirstOrDefault(row => row.Session.UserId == session.UserId);
        var account = existing is null ? new SavedSupabaseAccount(session, "", DateTimeOffset.UtcNow) : existing with { Session = session };
        var rows = Accounts.Where(row => row.Session.UserId != session.UserId).Append(account).OrderBy(row => row.AddedAt).ToArray();
        return new(rows, activate || ActiveUserId is null ? session.UserId : ActiveUserId);
    }
    internal SupabaseAccountsState Switch(string uid)
    {
        if (!Accounts.Any(row => row.Session.UserId == uid)) throw new InvalidOperationException("저장된 계정을 찾을 수 없습니다.");
        return this with { ActiveUserId = uid };
    }
    internal SupabaseAccountsState Remove(string uid)
    {
        if (!Accounts.Any(row => row.Session.UserId == uid)) throw new InvalidOperationException("저장된 계정을 찾을 수 없습니다.");
        var remaining = Accounts.Where(row => row.Session.UserId != uid).ToArray();
        return new(remaining, ActiveUserId == uid ? remaining.FirstOrDefault()?.Session.UserId : ActiveUserId);
    }
    internal SupabaseAccountsState Rename(string nickname) => this with
    {
        Accounts = Accounts.Select(row => row.Session.UserId == ActiveUserId ? row with { Nickname = nickname } : row).ToArray()
    };
    public override string ToString() => "Ping account state (sessions redacted)";
}
