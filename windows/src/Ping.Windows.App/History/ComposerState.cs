namespace Ping.Windows.App.History;

public sealed class ComposerState
{
    private readonly Dictionary<string, Draft> drafts = new(StringComparer.Ordinal);
    private string? roomId;
    private ComposerSendTicket? pending;
    public event Action? Changed;
    private Draft? Current => roomId is null ? null : drafts[roomId];
    public bool IsSending => pending is not null;
    public IEnumerable<string> ImagePaths => drafts.Values.Select(d => d.ImagePath).Append(pending?.ImagePath).OfType<string>();
    public bool CanSend => !IsSending && Current is { } draft && draft.Text.Trim().Length <= 2000
        && (!string.IsNullOrWhiteSpace(draft.Text) || !string.IsNullOrWhiteSpace(draft.ImagePath));
    public string Text { get => Current?.Text ?? ""; set { if (Current is { } d && d.Text != value) { d.Text = value; d.TextRevision++; Changed?.Invoke(); } } }
    public string? ImagePath { get => Current?.ImagePath; set { if (Current is { } d && d.ImagePath != value) { d.ImagePath = value; d.ImageRevision++; Changed?.Invoke(); } } }
    public HistoryReplyTarget? Reply { get => Current?.Reply; set { if (Current is { } d && !Equals(d.Reply, value)) { d.Reply = value; d.ReplyRevision++; Changed?.Invoke(); } } }

    public void SelectRoom(string? id)
    {
        if (roomId == id) return;
        roomId = id;
        if (id is not null) drafts.TryAdd(id, new Draft());
        Changed?.Invoke();
    }

    public ComposerSendTicket? BeginSend()
    {
        if (!CanSend || roomId is null || Current is not { } draft) return null;
        pending = new(roomId, draft.Text, draft.ImagePath, draft.Reply, draft.TextRevision, draft.ImageRevision, draft.ReplyRevision);
        Changed?.Invoke();
        return pending;
    }

    public void CompleteSend(ComposerSendTicket ticket, bool succeeded)
    {
        if (!ReferenceEquals(ticket, pending)) return;
        pending = null;
        if (succeeded && drafts.TryGetValue(ticket.RoomId, out var draft))
        {
            if (draft.TextRevision == ticket.TextRevision) { draft.Text = ""; draft.TextRevision++; }
            if (draft.ImageRevision == ticket.ImageRevision) { draft.ImagePath = null; draft.ImageRevision++; }
            if (draft.ReplyRevision == ticket.ReplyRevision) { draft.Reply = null; draft.ReplyRevision++; }
        }
        Changed?.Invoke();
    }

    private sealed class Draft
    {
        public string Text = "";
        public string? ImagePath;
        public HistoryReplyTarget? Reply;
        public long TextRevision, ImageRevision, ReplyRevision;
    }
}

public sealed record ComposerSendTicket(string RoomId, string Text, string? ImagePath, HistoryReplyTarget? Reply,
    long TextRevision, long ImageRevision, long ReplyRevision);

public static class ComposerKeyPolicy
{
    public static bool ShouldSubmitEnter(bool isComposing, bool shiftDown) => !isComposing && !shiftDown;
}

public enum ChatSendOutcome { NoContent, Sent }
