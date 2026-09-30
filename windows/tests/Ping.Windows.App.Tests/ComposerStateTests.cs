using Ping.Windows.App.History;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class ComposerStateTests
{
    [Fact]
    public void DraftAndImageBelongToTheirOwnRoom()
    {
        var state = new ComposerState();
        state.SelectRoom("a"); state.Text = "A draft"; state.ImagePath = "a.png";
        state.SelectRoom("b"); Assert.Equal("", state.Text); Assert.Null(state.ImagePath);
        state.Text = "B draft";
        state.SelectRoom("a"); Assert.Equal("A draft", state.Text); Assert.Equal("a.png", state.ImagePath);
    }

    [Fact]
    public void FailedSendRetainsDraftAndReleasesSendGuard()
    {
        var state = new ComposerState(); state.SelectRoom("a"); state.Text = "hello";
        var ticket = Assert.IsType<ComposerSendTicket>(state.BeginSend());
        Assert.Null(state.BeginSend());
        state.CompleteSend(ticket, false);
        Assert.Equal("hello", state.Text); Assert.False(state.IsSending); Assert.NotNull(state.BeginSend());
    }

    [Fact]
    public void SuccessfulSendCannotEraseNewTypingEvenWhenTextIsIdentical()
    {
        var state = new ComposerState(); state.SelectRoom("a"); state.Text = "hello"; state.ImagePath = "old.png";
        var ticket = state.BeginSend()!;
        state.Text = "new"; state.Text = "hello";
        state.CompleteSend(ticket, true);
        Assert.Equal("hello", state.Text); Assert.Null(state.ImagePath);
    }

    [Fact]
    public void SendCompletionClearsOnlySentRoom()
    {
        var state = new ComposerState(); state.SelectRoom("a"); state.Text = "send A";
        var ticket = state.BeginSend()!;
        state.SelectRoom("b"); state.Text = "keep B";
        state.CompleteSend(ticket, true);
        Assert.Equal("keep B", state.Text);
        state.SelectRoom("a"); Assert.Equal("", state.Text);
    }

    [Fact]
    public void EmptyOrTooLongDraftDoesNotStartSend()
    {
        var state = new ComposerState(); state.SelectRoom("a"); state.Text = "  "; Assert.Null(state.BeginSend());
        state.Text = new string('가', 2001); Assert.Null(state.BeginSend());
        state.Text = ""; state.ImagePath = "photo.png"; Assert.NotNull(state.BeginSend());
    }

    [Theory]
    [InlineData(false, false, true)]
    [InlineData(true, false, false)]
    [InlineData(false, true, false)]
    public void EnterDuringImeCompositionOrShiftDoesNotSend(bool isComposing, bool shift, bool expected) =>
        Assert.Equal(expected, ComposerKeyPolicy.ShouldSubmitEnter(isComposing, shift));
}
