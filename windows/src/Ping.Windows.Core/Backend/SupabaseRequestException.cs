using System.Net;
using System.Text.Json;

namespace Ping.Windows.Core.Backend;

public sealed class SupabaseRequestException : HttpRequestException
{
    public string? ErrorCode { get; }
    public TimeSpan? RetryAfter { get; }
    public bool IsSessionRejected { get; }

    public SupabaseRequestException(HttpStatusCode status, byte[] body, TimeSpan? retryAfter)
        : base($"Supabase request failed ({(int)status}).", null, status)
    {
        RetryAfter = retryAfter;
        try
        {
            using var document = JsonDocument.Parse(body);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return;
            ErrorCode = ReadString(document.RootElement, "code") ?? ReadString(document.RootElement, "error_code");
            var message = ReadString(document.RootElement, "message") ?? ReadString(document.RootElement, "msg")
                ?? ReadString(document.RootElement, "error_description");
            // Older Auth responses have no code; accept only the known refresh rejection text.
            IsSessionRejected = (status is HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
                && (ErrorCode is "refresh_token_not_found" or "refresh_token_already_used" or "session_not_found"
                    or "user_not_found" or "user_banned"
                    || string.Equals(message, "Invalid Refresh Token", StringComparison.OrdinalIgnoreCase));
        }
        catch (JsonException)
        {
            // HTML and gateway responses are request failures, not proof of lost identity.
        }
    }

    private static string? ReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
