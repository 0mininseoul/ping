using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.History;

public sealed class HistoryViewModel : INotifyPropertyChanged
{
    private readonly RoomService roomService;
    private readonly MessageService messageService;
    private readonly ChatMessageService chatService;
    private readonly ReactionService reactionService;
    private readonly StorageService storageService;
    private readonly Func<string?> currentUidProvider;
    private static readonly string[] QuickReactions = ["❤️", "👍", "👎", "😂", "‼️", "❓"];
    private Room? selectedRoom;
    private VideoHistoryItem? selectedVideo;
    private string statusMessage = "History";

    public HistoryViewModel(
        RoomService roomService,
        MessageService messageService,
        ChatMessageService chatService,
        ReactionService reactionService,
        StorageService storageService,
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

    public string SelectedRoomName => SelectedRoom?.Name ?? "No room selected";

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

    public async Task LoadSelectedRoomAsync(CancellationToken cancellationToken = default)
    {
        Videos.Clear();
        Chats.Clear();
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

        foreach (var video in videos)
        {
            Videos.Add(new VideoHistoryItem(video, QuickReactions, ReactionsFor(reactionMap, ReactionTargetKind.Video, video.Id)));
        }

        foreach (var chat in chats)
        {
            Chats.Add(new ChatHistoryItem(chat, QuickReactions, ReactionsFor(reactionMap, ReactionTargetKind.Chat, chat.Id)));
        }

        foreach (var reaction in reactions)
        {
            Reactions.Add(reaction);
        }

        await LoadChatImagesAsync(cancellationToken);
        await MarkSelectedRoomReadAsync(roomId, cancellationToken);
        StatusMessage = $"{Videos.Count} videos, {Chats.Count} chats, {Reactions.Count} reactions.";
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

        await chatService.SendChatAsync(
            roomId,
            trimmed,
            messageId: messageId,
            media: media,
            cancellationToken: cancellationToken);
        await LoadSelectedRoomAsync(cancellationToken);
        StatusMessage = hasImage ? "Image sent." : "Chat sent.";
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

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
