using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI.Xaml;
#endif

namespace Ping.Windows.App.History;

public sealed class HistoryViewModel : INotifyPropertyChanged
{
    private readonly RoomService roomService;
    private readonly MessageService messageService;
    private readonly ChatMessageService chatService;
    private readonly ReactionService reactionService;
    private readonly IChatMediaStorageService storageService;
    private readonly Func<string?> currentUidProvider;
    private static readonly string[] QuickReactions = ["❤️", "👍", "👎", "😂", "‼️", "❓"];
    private Room? selectedRoom;
    private VideoHistoryItem? selectedVideo;
    private TimelineHistoryItem? selectedTimelineItem;
    private HistoryReplyTarget? replyTarget;
    private string statusMessage = "History";

    public HistoryViewModel(
        RoomService roomService,
        MessageService messageService,
        ChatMessageService chatService,
        ReactionService reactionService,
        IChatMediaStorageService storageService,
        Func<string?> currentUidProvider)
    {
        this.roomService = roomService;
        this.messageService = messageService;
        this.chatService = chatService;
        this.reactionService = reactionService;
        this.storageService = storageService;
        this.currentUidProvider = currentUidProvider;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<Room> Rooms { get; } = [];

    public ObservableCollection<VideoHistoryItem> Videos { get; } = [];

    public ObservableCollection<ChatHistoryItem> Chats { get; } = [];

    public ObservableCollection<TimelineHistoryItem> Timeline { get; } = [];

    public ObservableCollection<MessageReaction> Reactions { get; } = [];

    public Room? SelectedRoom
    {
        get => selectedRoom;
        set
        {
            if (Equals(selectedRoom, value))
            {
                return;
            }

            selectedRoom = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(SelectedRoomName));
        }
    }

    public VideoHistoryItem? SelectedVideo
    {
        get => selectedVideo;
        set
        {
            selectedVideo = value;
            OnPropertyChanged();
        }
    }

    public TimelineHistoryItem? SelectedTimelineItem
    {
        get => selectedTimelineItem;
        set
        {
            if (ReferenceEquals(selectedTimelineItem, value))
            {
                return;
            }

            selectedTimelineItem = value;
            OnPropertyChanged();
            SelectedVideo = value?.Video;
        }
    }

    public HistoryReplyTarget? ReplyTarget
    {
        get => replyTarget;
        private set
        {
            replyTarget = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ReplyPreviewText));
            OnPropertyChanged(nameof(ReplyPreviewVisibility));
        }
    }

    public string SelectedRoomName => SelectedRoom?.Name ?? "No room selected";

    public string ReplyPreviewText => ReplyTarget?.DisplayText ?? string.Empty;

#if WINDOWS
    public Visibility ReplyPreviewVisibility => ReplyTarget is null ? Visibility.Collapsed : Visibility.Visible;
#else
    public bool ReplyPreviewVisibility => ReplyTarget is not null;
#endif

    public string StatusMessage
    {
        get => statusMessage;
        private set
        {
            if (string.Equals(statusMessage, value, StringComparison.Ordinal))
            {
                return;
            }

            statusMessage = value;
            OnPropertyChanged();
        }
    }

    public async Task LoadAsync(string? preferredRoomId = null, CancellationToken cancellationToken = default)
    {
        Rooms.Clear();
        foreach (var room in (await roomService.MyRoomsAsync(cancellationToken)).OrderBy(room => room.Name, StringComparer.OrdinalIgnoreCase))
        {
            Rooms.Add(room);
        }

        SelectedRoom = preferredRoomId is null
            ? Rooms.FirstOrDefault()
            : Rooms.FirstOrDefault(room => string.Equals(room.Id, preferredRoomId, StringComparison.Ordinal)) ?? Rooms.FirstOrDefault();
        await LoadSelectedRoomAsync(cancellationToken);
    }

    public async Task SelectRoomAsync(string roomId, CancellationToken cancellationToken = default)
    {
        if (Rooms.Count == 0)
        {
            await LoadAsync(roomId, cancellationToken);
            return;
        }

        SelectedRoom = Rooms.FirstOrDefault(room => string.Equals(room.Id, roomId, StringComparison.Ordinal)) ?? SelectedRoom;
        await LoadSelectedRoomAsync(cancellationToken);
    }

    public async Task FocusChatAsync(
        string roomId,
        string chatId,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(roomId) || string.IsNullOrWhiteSpace(chatId))
        {
            return;
        }

        await LoadAsync(roomId, cancellationToken);
        var row = Timeline.FirstOrDefault(candidate =>
            string.Equals(candidate.Chat?.Message.Id, chatId, StringComparison.Ordinal));
        SelectedTimelineItem = row;
        StatusMessage = row?.Chat is { } chat
            ? $"Focused chat from {chat.SenderNickname}."
            : "Chat not found in latest room history.";
    }

    public async Task LoadSelectedRoomAsync(CancellationToken cancellationToken = default)
    {
        var previousSelectedSortKind = SelectedTimelineItem?.SortKind;
        var previousSelectedSortId = SelectedTimelineItem?.SortId;
        SelectedTimelineItem = null;
        SelectedVideo = null;
        Videos.Clear();
        Chats.Clear();
        Timeline.Clear();
        Reactions.Clear();
        if (SelectedRoom?.Id is not { } roomId)
        {
            StatusMessage = "No room selected.";
            return;
        }

        var videos = await messageService.RoomMessagesAsync(roomId, cancellationToken: cancellationToken);
        var chats = await chatService.RoomChatMessagesAsync(roomId, cancellationToken: cancellationToken);

        var reactions = await reactionService.ReactionsAsync(
            chats.Where(chat => chat.Id is not null).Select(chat => chat.Id!).ToArray(),
            videos.Where(video => video.Id is not null).Select(video => video.Id!).ToArray(),
            cancellationToken);
        var reactionMap = ReactionMap(reactions);
        var currentUid = currentUidProvider();
        var chatById = chats
            .Where(chat => chat.Id is not null)
            .ToDictionary(chat => chat.Id!, StringComparer.Ordinal);
        var videoById = videos
            .Where(video => video.Id is not null)
            .ToDictionary(video => video.Id!, StringComparer.Ordinal);

        foreach (var video in videos)
        {
            var row = new VideoHistoryItem(video, QuickReactions, ReactionsFor(reactionMap, ReactionTargetKind.Video, video.Id), currentUid);
            Videos.Add(row);
        }

        foreach (var chat in chats)
        {
            var row = new ChatHistoryItem(
                chat,
                QuickReactions,
                ReactionsFor(reactionMap, ReactionTargetKind.Chat, chat.Id),
                currentUid,
                ReplyPreviewFor(chat, chatById, videoById));
            Chats.Add(row);
        }

        foreach (var reaction in reactions)
        {
            Reactions.Add(reaction);
        }

        RebuildTimeline();
        RestoreSelectedTimelineItem(previousSelectedSortKind, previousSelectedSortId);
        await LoadChatImagesAsync(cancellationToken);
        await MarkSelectedRoomReadAsync(roomId, cancellationToken);
        StatusMessage = $"{Videos.Count} videos, {Chats.Count} chats, {Reactions.Count} reactions.";
    }

    public void BeginReplyToChat(ChatHistoryItem item)
    {
        if (string.IsNullOrWhiteSpace(item.Message.Id))
        {
            return;
        }

        ReplyTarget = HistoryReplyTarget.ForChat(item.Message.Id, item.SenderNickname, item.PreviewText);
    }

    public void BeginReplyToVideo(VideoHistoryItem item)
    {
        if (string.IsNullOrWhiteSpace(item.Message.Id))
        {
            return;
        }

        var preview = item.Message.CaptureMode == CaptureMode.FaceOnly ? "Face video" : "Screen + face video";
        ReplyTarget = HistoryReplyTarget.ForVideo(item.Message.Id, item.SenderNickname, preview);
    }

    public void CancelReply()
    {
        ReplyTarget = null;
    }

    public async Task SendChatAsync(string body, string? localImagePath = null, CancellationToken cancellationToken = default)
    {
        if (SelectedRoom?.Id is not { } roomId)
        {
            return;
        }

        var trimmed = body.Trim();
        var hasImage = !string.IsNullOrWhiteSpace(localImagePath);
        if (!hasImage && string.IsNullOrWhiteSpace(trimmed))
        {
            return;
        }

        var reply = ReplyTarget;
        ChatMediaPayload? media = null;
        string? messageId = null;
        if (hasImage)
        {
            var uid = currentUidProvider();
            if (string.IsNullOrWhiteSpace(uid))
            {
                throw new InvalidOperationException("Supabase session is not ready.");
            }

            messageId = Guid.NewGuid().ToString();
            var upload = await storageService.UploadChatImageAsync(localImagePath!, uid, messageId, cancellationToken);
            media = new ChatMediaPayload(
                upload.Path,
                upload.MimeType,
                upload.Width,
                upload.Height,
                upload.FileName);
        }

        try
        {
            await chatService.SendChatAsync(
                roomId,
                trimmed,
                replyToChatId: reply?.ChatId,
                replyToVideoId: reply?.VideoId,
                messageId: messageId,
                media: media,
                cancellationToken: cancellationToken);
        }
        catch
        {
            if (media is not null)
            {
                await DeleteUploadedChatMediaQuietlyAsync(media.Path);
            }

            throw;
        }

        ReplyTarget = null;
        await LoadSelectedRoomAsync(cancellationToken);
        StatusMessage = hasImage ? "Image sent." : "Chat sent.";
    }

    private async Task DeleteUploadedChatMediaQuietlyAsync(string remotePath)
    {
        try
        {
            await storageService.DeleteChatMediaAsync(remotePath, CancellationToken.None);
        }
        catch (Exception)
        {
            // Preserve the original send failure; media cleanup is best-effort.
        }
    }

    public async Task ToggleReactionAsync(
        ReactionTargetKind targetKind,
        string? targetId,
        string emoji,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(targetId) || string.IsNullOrWhiteSpace(emoji))
        {
            return;
        }

        var added = await reactionService.ToggleAsync(targetKind, targetId, emoji, cancellationToken);
        await LoadSelectedRoomAsync(cancellationToken);
        StatusMessage = added ? "Reaction added." : "Reaction removed.";
    }

    public async Task DeleteChatAsync(ChatHistoryItem item, CancellationToken cancellationToken = default)
    {
        if (!item.IsMine || string.IsNullOrWhiteSpace(item.Message.Id))
        {
            return;
        }

        await chatService.DeleteChatAsync(item.Message.Id, cancellationToken);
        Chats.Remove(item);
        RemoveTimeline(item);
        RemoveReactions(ReactionTargetKind.Chat, item.Message.Id);
        if (string.Equals(SelectedTimelineItem?.Chat?.Message.Id, item.Message.Id, StringComparison.Ordinal))
        {
            SelectedTimelineItem = null;
        }
        if (string.Equals(ReplyTarget?.ChatId, item.Message.Id, StringComparison.Ordinal))
        {
            ReplyTarget = null;
        }

        StatusMessage = "Chat deleted.";
    }

    public async Task DeleteVideoAsync(VideoHistoryItem item, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(item.Message.Id))
        {
            return;
        }

        var currentUid = currentUidProvider();
        if (string.Equals(item.Message.SenderUid, currentUid, StringComparison.Ordinal))
        {
            await messageService.DeleteMessageAsync(item.Message.Id, cancellationToken);
        }
        else
        {
            await messageService.HideMessageForReceiverAsync(item.Message.Id, cancellationToken);
        }

        Videos.Remove(item);
        RemoveTimeline(item);
        RemoveReactions(ReactionTargetKind.Video, item.Message.Id);
        if (ReferenceEquals(SelectedVideo, item))
        {
            SelectedVideo = null;
        }
        if (string.Equals(SelectedTimelineItem?.Video?.Message.Id, item.Message.Id, StringComparison.Ordinal))
        {
            SelectedTimelineItem = null;
        }
        if (string.Equals(ReplyTarget?.VideoId, item.Message.Id, StringComparison.Ordinal))
        {
            ReplyTarget = null;
        }

        StatusMessage = "Video removed.";
    }

    public async Task SaveVideoAsync(
        VideoHistoryItem item,
        Func<VideoMessage, CancellationToken, Task> saveAsync,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(item);
        ArgumentNullException.ThrowIfNull(saveAsync);

        if (!item.CanSave)
        {
            StatusMessage = "Local save is not allowed for this video.";
            return;
        }

        await saveAsync(item.Message, cancellationToken);
        StatusMessage = "Video saved.";
    }

    public void ReportError(Exception exception)
    {
        StatusMessage = exception.Message;
    }

    private async Task LoadChatImagesAsync(CancellationToken cancellationToken)
    {
        foreach (var row in Chats.Where(row => row.HasImageAttachment))
        {
            try
            {
                var path = await storageService.DownloadChatMediaAsync(
                    row.Message.MediaPath!,
                    MediaFileExtension(row.Message),
                    cancellationToken);
                row.SetImagePath(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or InvalidOperationException or HttpRequestException)
            {
                row.SetAttachmentError();
            }
        }
    }

    private async Task MarkSelectedRoomReadAsync(string roomId, CancellationToken cancellationToken)
    {
        try
        {
            await chatService.MarkRoomReadAsync(roomId, cancellationToken);
        }
        catch (Exception ex) when (ex is HttpRequestException or InvalidOperationException)
        {
        }
    }

    private static Dictionary<string, List<ReactionAggregate>> ReactionMap(IEnumerable<MessageReaction> reactions)
    {
        var map = new Dictionary<string, List<ReactionAggregate>>(StringComparer.Ordinal);
        foreach (var reaction in reactions)
        {
            var key = ReactionKey(reaction.TargetKind, reaction.TargetId);
            if (!map.TryGetValue(key, out var values))
            {
                values = [];
                map[key] = values;
            }

            values.Add(new ReactionAggregate(
                reaction.TargetKind,
                reaction.TargetId,
                reaction.Emoji,
                reaction.TotalCount,
                reaction.MyReacted));
        }

        return map;
    }

    private static IReadOnlyList<ReactionAggregate> ReactionsFor(
        IReadOnlyDictionary<string, List<ReactionAggregate>> reactionMap,
        ReactionTargetKind kind,
        string? targetId) =>
        targetId is null
            ? []
            : reactionMap.TryGetValue(ReactionKey(kind, targetId), out var reactions)
                ? reactions.OrderByDescending(reaction => reaction.Count).ThenBy(reaction => reaction.Emoji, StringComparer.Ordinal).ToArray()
                : [];

    private static string ReactionKey(ReactionTargetKind kind, string targetId) =>
        $"{kind.ToWireValue()}:{targetId}";

    private static string MediaFileExtension(ChatMessage message)
    {
        var fileNameExtension = (Path.GetExtension(message.MediaFileName ?? string.Empty) ?? string.Empty).TrimStart('.');
        if (!string.IsNullOrWhiteSpace(fileNameExtension))
        {
            return fileNameExtension;
        }

        var pathExtension = (Path.GetExtension(message.MediaPath ?? string.Empty) ?? string.Empty).TrimStart('.');
        if (!string.IsNullOrWhiteSpace(pathExtension))
        {
            return pathExtension;
        }

        return message.MediaMimeType switch
        {
            "image/jpeg" => "jpg",
            "image/png" => "png",
            "image/heic" => "heic",
            "image/heif" => "heif",
            "image/gif" => "gif",
            "image/webp" => "webp",
            _ => "img"
        };
    }

    private static string? ReplyPreviewFor(
        ChatMessage message,
        IReadOnlyDictionary<string, ChatMessage> chatById,
        IReadOnlyDictionary<string, VideoMessage> videoById)
    {
        if (message.ReplyToChatId is { } chatId)
        {
            return chatById.TryGetValue(chatId, out var chat)
                ? $"{chat.SenderNickname}: {PreviewText(chat)}"
                : "Deleted message";
        }

        if (message.ReplyToVideoId is { } videoId)
        {
            return videoById.TryGetValue(videoId, out var video)
                ? $"{video.SenderNickname}: {(video.CaptureMode == CaptureMode.FaceOnly ? "Face video" : "Screen + face video")}"
                : "Deleted message";
        }

        return null;
    }

    private static string PreviewText(ChatMessage message)
    {
        var body = message.Body.Trim();
        if (!string.IsNullOrWhiteSpace(body))
        {
            return body.Length > 60 ? $"{body[..60]}..." : body;
        }

        return string.IsNullOrWhiteSpace(message.MediaPath) ? string.Empty : "Image";
    }

    private void RemoveReactions(ReactionTargetKind targetKind, string targetId)
    {
        for (var index = Reactions.Count - 1; index >= 0; index--)
        {
            var reaction = Reactions[index];
            if (reaction.TargetKind == targetKind && string.Equals(reaction.TargetId, targetId, StringComparison.Ordinal))
            {
                Reactions.RemoveAt(index);
            }
        }
    }

    private void RebuildTimeline()
    {
        Timeline.Clear();
        var rows = Videos
            .Select(video => new TimelineHistoryItem(video))
            .Concat(Chats.Select(chat => new TimelineHistoryItem(chat)))
            .OrderBy(row => row.CreatedAt ?? DateTimeOffset.MaxValue)
            .ThenBy(row => row.SortKind)
            .ThenBy(row => row.SortId, StringComparer.Ordinal);

        foreach (var row in rows)
        {
            Timeline.Add(row);
        }
    }

    private void RestoreSelectedTimelineItem(int? sortKind, string? sortId)
    {
        if (sortKind is null || string.IsNullOrWhiteSpace(sortId))
        {
            return;
        }

        SelectedTimelineItem = Timeline.FirstOrDefault(row =>
            row.SortKind == sortKind.Value
            && string.Equals(row.SortId, sortId, StringComparison.Ordinal));
    }

    private void RemoveTimeline(VideoHistoryItem item)
    {
        for (var index = Timeline.Count - 1; index >= 0; index--)
        {
            if (ReferenceEquals(Timeline[index].Video, item))
            {
                Timeline.RemoveAt(index);
            }
        }
    }

    private void RemoveTimeline(ChatHistoryItem item)
    {
        for (var index = Timeline.Count - 1; index >= 0; index--)
        {
            if (ReferenceEquals(Timeline[index].Chat, item))
            {
                Timeline.RemoveAt(index);
            }
        }
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed record HistoryReplyTarget(string? ChatId, string? VideoId, string Sender, string Preview)
{
    public string DisplayText => $"{Sender}: {Preview}";

    public static HistoryReplyTarget ForChat(string chatId, string sender, string preview) =>
        new(chatId, null, sender, string.IsNullOrWhiteSpace(preview) ? "Message" : preview);

    public static HistoryReplyTarget ForVideo(string videoId, string sender, string preview) =>
        new(null, videoId, sender, preview);
}
