namespace Ping.Windows.Core.Models;

public static class PingInviteLink
{
    private const string DefaultBaseUrl = "https://ping0min.vercel.app";

    public static Uri UrlFor(string token, string? baseUrl = null)
    {
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            baseUrl = Environment.GetEnvironmentVariable("PING_INVITE_BASE_URL");
        }

        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            baseUrl = DefaultBaseUrl;
        }

        return new Uri(new Uri(baseUrl.TrimEnd('/') + "/", UriKind.Absolute), $"invite/{Uri.EscapeDataString(token)}");
    }

    public static string ShareTextFor(string token, string? baseUrl = null) =>
        UrlFor(token, baseUrl).AbsoluteUri;

    public static string? TokenFrom(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        if (Uri.TryCreate(trimmed, UriKind.Absolute, out var uri))
        {
            return TokenFrom(uri);
        }

        return IsToken(trimmed) ? trimmed : null;
    }

    private static string? TokenFrom(Uri uri)
    {
        if (string.Equals(uri.Scheme, "ping", StringComparison.OrdinalIgnoreCase)
            && string.Equals(uri.Host, "invite", StringComparison.OrdinalIgnoreCase))
        {
            return FirstPathToken(uri);
        }

        var segments = uri.AbsolutePath
            .Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.UnescapeDataString)
            .ToArray();
        for (var index = 0; index < segments.Length - 1; index += 1)
        {
            if (string.Equals(segments[index], "invite", StringComparison.OrdinalIgnoreCase))
            {
                var token = segments[index + 1];
                return IsToken(token) ? token : null;
            }
        }

        var queryToken = QueryToken(uri);
        if (!string.IsNullOrWhiteSpace(queryToken))
        {
            return IsToken(queryToken) ? queryToken : null;
        }

        return null;
    }

    private static string? FirstPathToken(Uri uri)
    {
        var token = uri.AbsolutePath
            .Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.UnescapeDataString)
            .FirstOrDefault();
        return token is not null && IsToken(token) ? token : null;
    }

    private static string? QueryToken(Uri uri)
    {
        var query = uri.Query.TrimStart('?');
        foreach (var part in query.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var pair = part.Split('=', 2);
            if (pair.Length == 2 && string.Equals(Uri.UnescapeDataString(pair[0]), "token", StringComparison.Ordinal))
            {
                return Uri.UnescapeDataString(pair[1]);
            }
        }

        return null;
    }

    private static bool IsToken(string token) =>
        token.Length is >= 8 and <= 64
        && token.All(character =>
            char.IsAsciiLetterOrDigit(character)
            || character is '-' or '_');
}
