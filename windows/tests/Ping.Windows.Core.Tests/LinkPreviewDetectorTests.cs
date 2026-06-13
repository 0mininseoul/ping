using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class LinkPreviewDetectorTests
{
    [Fact]
    public void FirstUrl_DetectsHttpsAndTrimsTrailingPunctuation()
    {
        var url = LinkPreviewDetector.FirstUrl("check https://example.com/path?x=1).");

        Assert.Equal("https://example.com/path?x=1", url?.AbsoluteUri);
    }

    [Fact]
    public void FirstUrl_NormalizesBareWwwLink()
    {
        var url = LinkPreviewDetector.FirstUrl("www.example.com/ping");

        Assert.Equal("https://www.example.com/ping", url?.AbsoluteUri);
    }

    [Fact]
    public void OpenGraphParser_ExtractsCardMetadata()
    {
        const string Html = """
            <html><head>
            <meta property="og:title" content="Ping launch">
            <meta property="og:description" content="Three second video messages">
            <meta property="og:image" content="/card.png">
            </head></html>
            """;

        var metadata = OpenGraphParser.Parse(Html, new Uri("https://example.com/post"));

        Assert.Equal("Ping launch", metadata.Title);
        Assert.Equal("Three second video messages", metadata.Summary);
        Assert.Equal("https://example.com/card.png", metadata.ImageUrl?.AbsoluteUri);
    }
}
