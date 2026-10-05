using System.Net;
using System.Text.RegularExpressions;

namespace Ping.Windows.Core.Models;

public sealed record LinkPreviewMetadata(
    Uri Url,
    string DisplayHost,
    string? Title,
    string? Summary,
    Uri? ImageUrl,
    string? SiteName)
{
    public static LinkPreviewMetadata Fallback(Uri url) =>
        new(url, LinkPreviewDetector.DisplayHost(url), null, null, null, null);

    public string DisplayTitle => string.IsNullOrWhiteSpace(Title)
        ? (string.IsNullOrWhiteSpace(SiteName) ? DisplayHost : SiteName)
        : Title;
}

public sealed record DetectedLink(Uri Url, int Start, int Length);

public static partial class LinkPreviewDetector
{
    private static readonly char[] TrailingPunctuation = ['.', ',', '!', '?', ';', ':', ')', ']', '}', '。', '，', '！', '？'];

    public static Uri? FirstUrl(string? text) => Matches(text).FirstOrDefault(link => link.Url.Scheme is "http" or "https")?.Url;

    public static IReadOnlyList<DetectedLink> Matches(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return [];
        }

        var result = new List<DetectedLink>();
        foreach (Match match in UrlRegex().Matches(text))
        {
            var raw = TrimPunctuation(match.Value);
            if (match.Groups["email"].Success)
            {
                if (Uri.TryCreate(raw.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase) ? raw : "mailto:" + raw, UriKind.Absolute, out var email))
                    result.Add(new(email, match.Index, raw.Length));
            }
            else if (TryNormalize(raw, out var url))
            {
                result.Add(new(url, match.Index, raw.Length));
            }
        }

        return result;
    }

    private static string TrimPunctuation(string value)
    {
        while (value.Length > 0 && TrailingPunctuation.Contains(value[^1]))
        {
            var close = value[^1];
            var open = close switch { ')' => '(', ']' => '[', '}' => '{', _ => '\0' };
            if (open != '\0' && value.Count(c => c == close) <= value.Count(c => c == open)) break;
            value = value[..^1];
        }
        return value;
    }

    public static string DisplayHost(Uri url)
    {
        var host = url.Host;
        return host.StartsWith("www.", StringComparison.OrdinalIgnoreCase)
            ? host[4..]
            : host;
    }

    private static bool TryNormalize(string raw, out Uri url)
    {
        var value = !raw.Contains("://", StringComparison.Ordinal)
            ? $"https://{raw}"
            : raw;

        if (Uri.TryCreate(value, UriKind.Absolute, out url!)
            && (url.Scheme == Uri.UriSchemeHttp || url.Scheme == Uri.UriSchemeHttps)
            && !string.IsNullOrWhiteSpace(url.Host))
        {
            return true;
        }

        url = null!;
        return false;
    }

    [GeneratedRegex("""https?://[^\s<>"']+|(?<![\p{L}\p{N}_@/:])(?:(?<email>(?:mailto:)?[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,63}(?:\?[^\s<>"']*)?)|(?:[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?\.)+[a-z]{2,63}(?::[0-9]+)?(?:[/\?#][^\s<>"']*)?)""", RegexOptions.IgnoreCase)]
    private static partial Regex UrlRegex();
}

public static partial class OpenGraphParser
{
    private static readonly HashSet<string> TitleKeys = new(StringComparer.OrdinalIgnoreCase) { "og:title", "twitter:title" };
    private static readonly HashSet<string> SummaryKeys = new(StringComparer.OrdinalIgnoreCase) { "og:description", "twitter:description", "description" };
    private static readonly HashSet<string> SiteNameKeys = new(StringComparer.OrdinalIgnoreCase) { "og:site_name" };
    private static readonly HashSet<string> ImageKeys = new(StringComparer.OrdinalIgnoreCase) { "og:image", "og:image:url", "twitter:image" };

    public static LinkPreviewMetadata Parse(string html, Uri pageUrl)
    {
        var title = MetaContent(html, TitleKeys) ?? TitleContent(html);
        var summary = MetaContent(html, SummaryKeys);
        var siteName = MetaContent(html, SiteNameKeys);
        var image = MetaContent(html, ImageKeys);
        var imageUrl = ResolveUrl(image, pageUrl);

        return new LinkPreviewMetadata(
            pageUrl,
            LinkPreviewDetector.DisplayHost(pageUrl),
            title,
            summary,
            imageUrl,
            siteName);
    }

    private static string? MetaContent(string html, ISet<string> keys)
    {
        foreach (Match tagMatch in MetaTagRegex().Matches(html))
        {
            var attrs = Attributes(tagMatch.Value);
            var key = attrs.TryGetValue("property", out var property)
                ? property
                : attrs.TryGetValue("name", out var name) ? name : null;
            if (key is null || !keys.Contains(key.ToLowerInvariant()))
            {
                continue;
            }

            if (attrs.TryGetValue("content", out var content) && !string.IsNullOrWhiteSpace(content))
            {
                return HtmlDecode(content.Trim());
            }
        }

        return null;
    }

    private static Dictionary<string, string> Attributes(string tag)
    {
        var attrs = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match match in AttributeRegex().Matches(tag))
        {
            attrs[match.Groups[1].Value] = HtmlDecode(match.Groups[3].Value);
        }

        return attrs;
    }

    private static string? TitleContent(string html)
    {
        var match = TitleRegex().Match(html);
        return match.Success ? HtmlDecode(match.Groups[1].Value.Trim()) : null;
    }

    private static Uri? ResolveUrl(string? value, Uri pageUrl)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        return Uri.TryCreate(pageUrl, value, out var resolved) ? resolved : null;
    }

    private static string HtmlDecode(string value) => WebUtility.HtmlDecode(value);

    [GeneratedRegex("""<meta\b[^>]*>""", RegexOptions.IgnoreCase)]
    private static partial Regex MetaTagRegex();

    [GeneratedRegex("""([A-Za-z_:][A-Za-z0-9_:\.-]*)\s*=\s*(['"])(.*?)\2""", RegexOptions.IgnoreCase)]
    private static partial Regex AttributeRegex();

    [GeneratedRegex("""<title\b[^>]*>(.*?)</title>""", RegexOptions.IgnoreCase | RegexOptions.Singleline)]
    private static partial Regex TitleRegex();
}

public interface ILinkPreviewService
{
    Task<LinkPreviewMetadata> MetadataAsync(Uri url, CancellationToken cancellationToken = default);
}

public sealed class LinkPreviewService : ILinkPreviewService
{
    private readonly HttpClient httpClient;
    private readonly Dictionary<Uri, LinkPreviewMetadata> cache = new();

    public LinkPreviewService(HttpClient? httpClient = null)
    {
        this.httpClient = httpClient ?? new HttpClient();
    }

    public async Task<LinkPreviewMetadata> MetadataAsync(Uri url, CancellationToken cancellationToken = default)
    {
        if (cache.TryGetValue(url, out var cached))
        {
            return cached;
        }

        LinkPreviewMetadata metadata;
        try
        {
            var html = await httpClient.GetStringAsync(url, cancellationToken).ConfigureAwait(false);
            metadata = OpenGraphParser.Parse(html, url);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            metadata = LinkPreviewMetadata.Fallback(url);
        }

        cache[url] = metadata;
        return metadata;
    }
}
