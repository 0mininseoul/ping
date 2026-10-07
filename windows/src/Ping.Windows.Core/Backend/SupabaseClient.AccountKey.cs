using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Backend;

public sealed class ConnectedPingAccount
{
    internal ConnectedPingAccount(SupabaseSession session, string nickname) { Session = session; Nickname = nickname; }
    internal SupabaseSession Session { get; }
    public string Nickname { get; }
    public string UserId => Session.UserId;
    public override string ToString() => "Connected Ping account (session redacted)";
}

public sealed class AccountKeyException(string message) : Exception(message);

public sealed partial class SupabaseClient
{
    private static readonly Uri AccountKeyEndpoint = new("https://0minping.vercel.app/api/account-key");
    private const string AccountKeyProject = "https://qxjtprxvjmaxlbtljcjw.supabase.co";

    public async Task<bool> GetAccountKeyStatusAsync(CancellationToken token = default)
    {
        var current = await AuthenticatedSessionAsync(token).ConfigureAwait(false);
        var response = await SendAccountKeyRequestAsync(new { action = "status" }, current.AccessToken, token).ConfigureAwait(false);
        using var json = JsonDocument.Parse(response);
        return json.RootElement.GetProperty("enabled").GetBoolean();
    }

    public async Task SetAccountKeyAsync(string key, CancellationToken token = default)
    {
        ValidateAccountKey(key);
        var current = await AuthenticatedSessionAsync(token).ConfigureAwait(false);
        await SendAccountKeyRequestAsync(new { action = "set", key }, current.AccessToken, token).ConfigureAwait(false);
    }

    public async Task<ConnectedPingAccount> AuthenticateAccountKeyAsync(string nickname, string key, CancellationToken token = default)
    {
        ValidateAccountKey(key);
        var name = SearchableText.Normalize(nickname);
        if (name.Length is < 1 or > 256) throw new AccountKeyException("닉네임을 입력해 주세요.");
        var bytes = await SendAccountKeyRequestAsync(new { action = "login", nickname = name, key }, null, token).ConfigureAwait(false);
        var result = JsonSerializer.Deserialize<AccountKeyAuthResponse>(bytes, JsonOptions.Supabase)
            ?? throw new AccountKeyException("계정 연결 응답을 읽지 못했어요.");
        if (result.ProjectUrl != AccountKeyProject || !Guid.TryParse(result.User?.Id, out _) ||
            string.IsNullOrWhiteSpace(result.AccessToken) || string.IsNullOrWhiteSpace(result.RefreshToken) ||
            result.ExpiresAt is null || string.IsNullOrWhiteSpace(result.Nickname))
            throw new AccountKeyException("계정 연결 응답이 올바르지 않아요.");
        var config = await LoadConfigurationAsync(token).ConfigureAwait(false);
        using var check = new HttpRequestMessage(HttpMethod.Get, new Uri($"{config.AuthUrl}/user"));
        check.Headers.Add("apikey", config.AnonKey);
        check.Headers.Authorization = new AuthenticationHeaderValue("Bearer", result.AccessToken);
        var owner = JsonSerializer.Deserialize<SupabaseAuthUser>(await SendAsync(check, token).ConfigureAwait(false), JsonOptions.Supabase);
        if (owner is null || owner.Id != result.User!.Id) throw new AccountKeyException("계정 연결 응답이 올바르지 않아요.");
        var expires = DateTimeOffset.FromUnixTimeSeconds(result.ExpiresAt.Value);
        if (expires <= DateTimeOffset.UtcNow) throw new AccountKeyException("연결 시간이 지났어요. 다시 입력해 주세요.");
        return new(new(result.AccessToken, result.RefreshToken, expires, owner.Id), result.Nickname);
    }

    public async Task ImportConnectedAccountAsync(ConnectedPingAccount account, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(account);
        await authLock.WaitAsync(token).ConfigureAwait(false);
        try
        {
            ThrowIfRetired();
            // Read after the old coordinator has retired, preserving its latest refresh tokens.
            accounts = await sessionStore.LoadAccountsAsync(token).ConfigureAwait(false);
            session = accounts.ActiveSession;
            await CommitAccountsLockedAsync(accounts.Upsert(account.Session, activate: true).Rename(account.Nickname), token).ConfigureAwait(false);
        }
        finally { authLock.Release(); }
    }

    private async Task<byte[]> SendAccountKeyRequestAsync(object body, string? accessToken, CancellationToken token)
    {
        var config = await LoadConfigurationAsync(token).ConfigureAwait(false);
        if (config.Url.ToString().TrimEnd('/') != AccountKeyProject)
            throw new AccountKeyException("이 Supabase 프로젝트에서는 계정 연결을 사용할 수 없어요.");
        using var request = new HttpRequestMessage(HttpMethod.Post, AccountKeyEndpoint);
        request.Content = new ByteArrayContent(JsonSerializer.SerializeToUtf8Bytes(body, JsonOptions.Supabase));
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        if (accessToken is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, requestLifetime.Token);
        linked.CancelAfter(TimeSpan.FromSeconds(15));
        HttpResponseMessage response;
        try { response = await httpClient.SendAsync(request, linked.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested && !requestLifetime.IsCancellationRequested)
        { throw new AccountKeyException("연결 응답이 오래 걸리고 있어요. 잠시 후 다시 시도해 주세요."); }
        using var disposeResponse = response;
        var bytes = await response.Content.ReadAsByteArrayAsync(linked.Token).ConfigureAwait(false);
        if (response.IsSuccessStatusCode) return bytes;
        string? error = null;
        try { using var json = JsonDocument.Parse(bytes); error = json.RootElement.GetProperty("error").GetString(); }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException) { }
        throw new AccountKeyException(error switch
        {
            "invalid_credentials" => "닉네임 또는 비밀키가 맞지 않아요. 기존 기기에서 키를 설정했는지 확인해 주세요.",
            "session_required" => "현재 계정의 연결이 만료됐어요. 계정을 다시 연결해 주세요.",
            "key_length" => "비밀키는 12~128자로 정해 주세요.",
            "key_conflict" => "이 닉네임에서 사용할 수 없는 키예요. 다른 비밀키를 정해 주세요.",
            "profile_required" => "닉네임을 먼저 저장해 주세요.",
            "identity_conflict" => "이 계정에는 다른 인증 방식이 연결되어 있어 비밀키를 설정할 수 없어요.",
            _ when response.StatusCode == HttpStatusCode.TooManyRequests => "시도가 많아요. 잠시 후 다시 시도해 주세요.",
            _ => "계정 연결 서비스가 아직 준비되지 않았거나 연결할 수 없어요. 잠시 후 다시 시도해 주세요."
        });
    }

    private static void ValidateAccountKey(string key)
    {
        if (key.Length is < 12 or > 128) throw new AccountKeyException("비밀키는 12~128자로 입력해 주세요. 공백과 대소문자를 구분합니다.");
    }
}

internal sealed record AccountKeyAuthResponse(
    [property: JsonPropertyName("access_token")] string AccessToken,
    [property: JsonPropertyName("refresh_token")] string RefreshToken,
    [property: JsonPropertyName("expires_at")] long? ExpiresAt,
    [property: JsonPropertyName("user")] SupabaseAuthUser? User,
    [property: JsonPropertyName("nickname")] string Nickname,
    [property: JsonPropertyName("project_url")] string ProjectUrl)
{
    public override string ToString() => "Ping account-key authentication response (redacted)";
}
