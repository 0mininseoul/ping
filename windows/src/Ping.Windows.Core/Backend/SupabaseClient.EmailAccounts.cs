using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Backend;

public sealed partial class SupabaseClient
{
    public async Task<EmailAccountStatus> GetEmailAccountStatusAsync(CancellationToken token = default)
    {
        var current = await AuthenticatedSessionAsync(token).ConfigureAwait(false);
        var user = await ReadEmailUserAsync(current, token).ConfigureAwait(false);
        return new(current.UserId, user.Email, user.EmailConfirmedAt is not null);
    }

    public async Task RequestAccountEmailAsync(string email, string expectedUserId, CancellationToken token = default)
    {
        var address = EmailAccountInput.Normalize(email);
        _ = await AuthenticatedSessionAsync(token).ConfigureAwait(false);
        await authLock.WaitAsync(token).ConfigureAwait(false);
        try
        {
            ThrowIfRetired();
            var current = session ?? throw new SupabaseAccountRequiredException();
            if (current.UserId != expectedUserId) throw new InvalidOperationException("Active account changed.");
            var user = await ReadEmailUserAsync(current, token).ConfigureAwait(false);
            if (user.EmailConfirmedAt is not null && !string.IsNullOrWhiteSpace(user.Email))
                throw new InvalidOperationException("This account already has a confirmed email.");
            var config = await LoadConfigurationAsync(token).ConfigureAwait(false);
            using var request = CreateAuthRequest(config, HttpMethod.Put, new Uri($"{config.AuthUrl}/user"), new { email = address });
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", current.AccessToken);
            var data = await SendAsync(request, token).ConfigureAwait(false);
            var updated = JsonSerializer.Deserialize<EmailAuthUser>(data, JsonOptions.Supabase);
            if (updated?.Id != current.UserId) throw new InvalidOperationException("Email linking returned a different account.");
        }
        finally { authLock.Release(); }
    }

    public async Task RequestEmailSignInAsync(string email, CancellationToken token = default)
    {
        var config = await LoadConfigurationAsync(token).ConfigureAwait(false);
        using var request = CreateAuthRequest(config, HttpMethod.Post, new Uri($"{config.AuthUrl}/otp"),
            new { email = EmailAccountInput.Normalize(email), create_user = false });
        _ = await SendAsync(request, token).ConfigureAwait(false);
    }

    public async Task<EmailAuthenticationResult> VerifyEmailAccountAsync(string email, string code,
        EmailAuthenticationPurpose purpose, string? expectedUserId, CancellationToken token = default)
    {
        if (!Enum.IsDefined(purpose)) throw new ArgumentOutOfRangeException(nameof(purpose));
        if (purpose == EmailAuthenticationPurpose.LinkCurrentAccount && string.IsNullOrWhiteSpace(expectedUserId))
            throw new ArgumentException("Account identity is required for linking.");
        var address = EmailAccountInput.Normalize(email);
        var config = await LoadConfigurationAsync(token).ConfigureAwait(false);
        using var request = CreateAuthRequest(config, HttpMethod.Post, new Uri($"{config.AuthUrl}/verify"),
            new { email = address, token = EmailAccountInput.Code(code), type = purpose == EmailAuthenticationPurpose.SignIn ? "email" : "email_change" });
        var data = await SendAsync(request, token).ConfigureAwait(false);
        var response = JsonSerializer.Deserialize<SupabaseAuthResponse>(data, JsonOptions.Supabase);
        using var document = JsonDocument.Parse(data);
        if (response is null || response.User is null || string.IsNullOrWhiteSpace(response.User.Id)
            || string.IsNullOrWhiteSpace(response.AccessToken) || string.IsNullOrWhiteSpace(response.RefreshToken)
            || !document.RootElement.TryGetProperty("user", out var userElement))
            throw new InvalidOperationException("Email verification did not return a session.");
        var user = userElement.Deserialize<EmailAuthUser>(JsonOptions.Supabase);
        var expiry = response.ExpiresAt is { } expiresAt ? DateTimeOffset.FromUnixTimeSeconds(expiresAt)
            : DateTimeOffset.UtcNow.AddSeconds(response.ExpiresIn);
        var verified = new SupabaseSession(response.AccessToken, response.RefreshToken, expiry, response.User.Id);
        if (purpose == EmailAuthenticationPurpose.LinkCurrentAccount && verified.UserId != expectedUserId)
            throw new InvalidOperationException("Email linking returned a different account.");
        if (user is null || user.Id != verified.UserId || user.IsAnonymous || user.EmailConfirmedAt is null
            || expiry <= DateTimeOffset.UtcNow || !string.Equals(user.Email, address, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Email ownership was not confirmed.");
        return new(verified, config.Url, address);
    }

    public async Task AcceptEmailAccountAsync(EmailAuthenticationResult authentication, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(authentication);
        var config = await LoadConfigurationAsync(token).ConfigureAwait(false);
        if (config.Url != authentication.ProjectUrl) throw new InvalidOperationException("Email account belongs to a different backend.");
        await authLock.WaitAsync(token).ConfigureAwait(false);
        try
        {
            await LoadAccountsLockedAsync(token).ConfigureAwait(false);
            var verified = authentication.Session;
            if (verified.NeedsRefresh)
            {
                verified = await RefreshSessionAsync(verified.RefreshToken, token).ConfigureAwait(false);
                authentication.RetainRefreshedSession(verified);
            }
            if (verified.UserId != authentication.UserId) throw new InvalidOperationException("Email session identity changed.");
            await CommitAccountsLockedAsync(accounts!.Upsert(verified, activate: true), token).ConfigureAwait(false);
        }
        finally { authLock.Release(); }
    }

    private async Task<EmailAuthUser> ReadEmailUserAsync(SupabaseSession authenticated, CancellationToken token)
    {
        var config = await LoadConfigurationAsync(token).ConfigureAwait(false);
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri($"{config.AuthUrl}/user"));
        request.Headers.Add("apikey", config.AnonKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authenticated.AccessToken);
        var data = await SendAsync(request, token).ConfigureAwait(false);
        var user = JsonSerializer.Deserialize<EmailAuthUser>(data, JsonOptions.Supabase);
        if (user is null || user.Id != authenticated.UserId) throw new InvalidOperationException("Authenticated user identity changed.");
        return user;
    }
}

internal sealed record EmailAuthUser(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("email")] string? Email,
    [property: JsonPropertyName("email_confirmed_at")] DateTimeOffset? EmailConfirmedAt,
    [property: JsonPropertyName("is_anonymous")] bool IsAnonymous);
