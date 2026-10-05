using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class LinkPreviewDetectorTests
{
    [Theory]
    [InlineData("qa@example..com")]
    [InlineData("qa@.example.com")]
    public void Matches_InvalidEmailKeepsConversationReadable(string input)
    {
        Assert.Empty(LinkPreviewDetector.Matches(input));
        Assert.Null(LinkPreviewDetector.FirstUrl(input));
        Assert.Equal("https://example.org/", Assert.Single(LinkPreviewDetector.Matches(input + " 그리고 https://example.org")).Url.AbsoluteUri);
    }
    [Fact]
    public void FirstUrl_DetectsBareDomainInConversation()
    {
        Assert.Equal("https://example.com/help", LinkPreviewDetector.FirstUrl("문서는 example.com/help 에 있어요")?.AbsoluteUri);
    }

    [Fact]
    public void Matches_PreservesAllUrlRangesAfterEmojiAndPunctuation()
    {
        var links = LinkPreviewDetector.Matches("🙂 https://a.test/x 와 www.b.test.");
        Assert.Collection(links,
            link => { Assert.Equal("https://a.test/x", link.Url.AbsoluteUri); Assert.Equal(3, link.Start); Assert.Equal(16, link.Length); },
            link => { Assert.Equal("https://www.b.test/", link.Url.AbsoluteUri); Assert.Equal(22, link.Start); Assert.Equal(10, link.Length); });
    }

    [Fact]
    public void Matches_UsesEmailHandlerWithoutFetchingEmailPreview()
    {
        var links = LinkPreviewDetector.Matches("qa@example.com 그리고 https://example.org");
        Assert.Equal("mailto:qa@example.com", links[0].Url.AbsoluteUri);
        Assert.Equal("https://example.org/", LinkPreviewDetector.FirstUrl("qa@example.com 그리고 https://example.org")?.AbsoluteUri);
        Assert.Null(LinkPreviewDetector.FirstUrl("qa@example.com"));
    }

    [Theory]
    [InlineData("https://example.com/a_(b)", "https://example.com/a_(b)")]
    [InlineData("(https://example.com/a_(b)).", "https://example.com/a_(b)")]
    [InlineData("HTTPS://example.com/x。", "https://example.com/x")]
    public void Matches_KeepsUrlParenthesesAndDropsSentencePunctuation(string input, string expected) =>
        Assert.Equal(expected, Assert.Single(LinkPreviewDetector.Matches(input)).Url.AbsoluteUri);

    [Theory]
    [InlineData("ftp://example.com")]
    [InlineData("javascript:example.com")]
    [InlineData("file:///example.com")]
    public void Matches_DoesNotTurnOtherSchemesIntoWebLinks(string input) => Assert.Empty(LinkPreviewDetector.Matches(input));
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
