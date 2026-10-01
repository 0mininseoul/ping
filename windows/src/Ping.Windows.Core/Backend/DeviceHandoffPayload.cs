using System.Globalization;
using System.Text.Json;

namespace Ping.Windows.Core.Backend;

public sealed class DeviceHandoffPayload
{
    private readonly SupabaseConfiguration configuration;
    private readonly SupabaseSession session;
    internal DeviceHandoffPayload(SupabaseConfiguration configuration, SupabaseSession session)
        => (this.configuration, this.session) = (configuration, session);
    public string UserId => session.UserId;
    public DateTimeOffset ExpiresAt => session.ExpiresAt;
    public byte[] EncodeUtf8() => JsonSerializer.SerializeToUtf8Bytes(new
    {
        url = configuration.Url.AbsoluteUri,
        anonKey = configuration.AnonKey,
        accessToken = session.AccessToken,
        refreshToken = session.RefreshToken,
        expiresAt = session.ExpiresAt.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
        userId = session.UserId
    });
    public override string ToString() => "Ping device handoff (session redacted)";
}
