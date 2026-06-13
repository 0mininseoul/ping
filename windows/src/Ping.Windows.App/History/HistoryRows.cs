using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
#endif

namespace Ping.Windows.App.History;

public sealed class TimelineHistoryItem
{
    public TimelineHistoryItem(VideoHistoryItem video)
    {
        Video = video;
    }

    public TimelineHistoryItem(ChatHistoryItem chat)
    {
        Chat = chat;
    }

    public VideoHistoryItem? Video { get; }

    public ChatHistoryItem? Chat { get; }

    public DateTimeOffset? CreatedAt => Video?.Message.CreatedAt ?? Chat?.Message.CreatedAt;

    public string SortId => Video?.Message.Id ?? Chat?.Message.Id ?? string.Empty;

    public int SortKind => Video is not null ? 0 : 1;

#if WINDOWS
    public Visibility VideoVisibility => Video is null ? Visibility.Collapsed : Visibility.Visible;

    public Visibility ChatVisibility => Chat is null ? Visibility.Collapsed : Visibility.Visible;
#else
    public bool VideoVisibility => Video is not null;

    public bool ChatVisibility => Chat is not null;
#endif
}

public sealed class VideoHistoryItem : INotifyPropertyChanged
{
#if WINDOWS
    private BitmapImage? thumbnailSource;
#else
    private Uri? thumbnailSource;
#endif

    public VideoHistoryItem(
        VideoMessage message,
        IReadOnlyCollection<string> quickReactions,
        IReadOnlyCollection<ReactionAggregate> reactions,
        string? currentUid = null)
    {
        Message = message;
        Reactions = new ObservableCollection<ReactionAggregate>(reactions);
        QuickReactions = message.Id is null
            ? []
            : quickReactions.Select(emoji => new ReactionChoice(ReactionTargetKind.Video, message.Id, emoji)).ToArray();
        IsMine = string.Equals(message.SenderUid, currentUid, StringComparison.Ordinal);
        CanSave = message.CanBeSavedLocally(currentUid);
    }

    public VideoMessage Message { get; }

    public ObservableCollection<ReactionAggregate> Reactions { get; }

    public IReadOnlyList<ReactionChoice> QuickReactions { get; }

    public string SenderNickname => Message.SenderNickname;

    public string VideoId => Message.VideoId;

    public CaptureMode CaptureMode => Message.CaptureMode;

    public bool IsMine { get; }

    public bool CanSave { get; }

    public event PropertyChangedEventHandler? PropertyChanged;

#if WINDOWS
    public Visibility SaveVisibility => CanSave ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ThumbnailVisibility => thumbnailSource is null ? Visibility.Collapsed : Visibility.Visible;

    public Visibility ThumbnailPlaceholderVisibility => thumbnailSource is null ? Visibility.Visible : Visibility.Collapsed;

    public BitmapImage? ThumbnailSource
#else
    public bool SaveVisibility => CanSave;

    public bool ThumbnailVisibility => thumbnailSource is not null;

    public bool ThumbnailPlaceholderVisibility => thumbnailSource is null;

    public Uri? ThumbnailSource
#endif
    {
        get => thumbnailSource;
        private set
        {
            thumbnailSource = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ThumbnailVisibility));
            OnPropertyChanged(nameof(ThumbnailPlaceholderVisibility));
        }
    }

#if WINDOWS
    public void SetThumbnail(BitmapImage image) => ThumbnailSource = image;
#endif

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class ChatHistoryItem : INotifyPropertyChanged
{
#if WINDOWS
    private BitmapImage? imageSource;
    private BitmapImage? linkPreviewImageSource;
#else
    private Uri? imageSource;
    private Uri? linkPreviewImageSource;
#endif
    private string attachmentStatus;
    private LinkPreviewMetadata? linkPreview;

    public ChatHistoryItem(
        ChatMessage message,
        IReadOnlyCollection<string> quickReactions,
        IReadOnlyCollection<ReactionAggregate> reactions,
        string? currentUid = null,
        string? replyPreview = null)
    {
        Message = message;
        Reactions = new ObservableCollection<ReactionAggregate>(reactions);
        QuickReactions = message.Id is null
            ? []
            : quickReactions.Select(emoji => new ReactionChoice(ReactionTargetKind.Chat, message.Id, emoji)).ToArray();
        attachmentStatus = message.MediaFileName ?? (HasImageAttachment ? "Image attachment" : string.Empty);
        IsMine = string.Equals(message.SenderUid, currentUid, StringComparison.Ordinal);
        ReplyPreview = replyPreview ?? string.Empty;
        LinkPreviewUrl = LinkPreviewDetector.FirstUrl(Message.Body);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ChatMessage Message { get; }

    public ObservableCollection<ReactionAggregate> Reactions { get; }

    public IReadOnlyList<ReactionChoice> QuickReactions { get; }

    public string SenderNickname => Message.SenderNickname;

    public string Body => Message.Body;

    public string MediaFileName => Message.MediaFileName ?? string.Empty;

    public bool HasImageAttachment => !string.IsNullOrWhiteSpace(Message.MediaPath);

    public bool IsMine { get; }

    public string ReplyPreview { get; }

    public Uri? LinkPreviewUrl { get; }

    public string LinkPreviewTitle => linkPreview?.DisplayTitle
        ?? (LinkPreviewUrl is null ? string.Empty : LinkPreviewDetector.DisplayHost(LinkPreviewUrl));

    public string LinkPreviewSummary => linkPreview?.Summary ?? string.Empty;

    public string LinkPreviewHost => linkPreview?.DisplayHost
        ?? (LinkPreviewUrl is null ? string.Empty : LinkPreviewDetector.DisplayHost(LinkPreviewUrl));

    public string PreviewText
    {
        get
        {
            var body = Body.Trim();
            if (!string.IsNullOrWhiteSpace(body))
            {
                return body.Length > 60 ? $"{body[..60]}..." : body;
            }

            return HasImageAttachment ? "Image" : string.Empty;
        }
    }

#if WINDOWS
    public Visibility AttachmentVisibility => HasImageAttachment ? Visibility.Visible : Visibility.Collapsed;

    public Visibility DeleteVisibility => IsMine ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ImageVisibility => imageSource is null ? Visibility.Collapsed : Visibility.Visible;

    public Visibility ReplyPreviewVisibility => string.IsNullOrWhiteSpace(ReplyPreview) ? Visibility.Collapsed : Visibility.Visible;

    public Visibility LinkPreviewVisibility => LinkPreviewUrl is null ? Visibility.Collapsed : Visibility.Visible;

    public Visibility LinkPreviewSummaryVisibility => string.IsNullOrWhiteSpace(LinkPreviewSummary) ? Visibility.Collapsed : Visibility.Visible;

    public Visibility LinkPreviewImageVisibility => linkPreviewImageSource is null ? Visibility.Collapsed : Visibility.Visible;

    public BitmapImage? LinkPreviewImageSource => linkPreviewImageSource;

    public BitmapImage? ImageSource
#else
    public bool AttachmentVisibility => HasImageAttachment;

    public bool DeleteVisibility => IsMine;

    public bool ImageVisibility => imageSource is not null;

    public bool ReplyPreviewVisibility => !string.IsNullOrWhiteSpace(ReplyPreview);

    public bool LinkPreviewVisibility => LinkPreviewUrl is not null;

    public bool LinkPreviewSummaryVisibility => !string.IsNullOrWhiteSpace(LinkPreviewSummary);

    public bool LinkPreviewImageVisibility => linkPreviewImageSource is not null;

    public Uri? LinkPreviewImageSource => linkPreviewImageSource;

    public Uri? ImageSource
#endif
    {
        get => imageSource;
        private set
        {
            imageSource = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ImageVisibility));
        }
    }

    public string AttachmentStatus
    {
        get => attachmentStatus;
        private set
        {
            attachmentStatus = value;
            OnPropertyChanged();
        }
    }

    public void SetImagePath(string localPath)
    {
#if WINDOWS
        ImageSource = new BitmapImage(new Uri(Path.GetFullPath(localPath)));
#else
        ImageSource = new Uri(Path.GetFullPath(localPath));
#endif
        AttachmentStatus = string.IsNullOrWhiteSpace(MediaFileName) ? "Image" : MediaFileName;
    }

    public void SetLinkPreview(LinkPreviewMetadata metadata)
    {
        linkPreview = metadata;
#if WINDOWS
        linkPreviewImageSource = metadata.ImageUrl is null ? null : new BitmapImage(metadata.ImageUrl);
#else
        linkPreviewImageSource = metadata.ImageUrl;
#endif
        OnPropertyChanged(nameof(LinkPreviewTitle));
        OnPropertyChanged(nameof(LinkPreviewSummary));
        OnPropertyChanged(nameof(LinkPreviewHost));
        OnPropertyChanged(nameof(LinkPreviewSummaryVisibility));
        OnPropertyChanged(nameof(LinkPreviewImageVisibility));
        OnPropertyChanged(nameof(LinkPreviewImageSource));
    }

    public void SetAttachmentError()
    {
        ImageSource = null;
        AttachmentStatus = string.IsNullOrWhiteSpace(MediaFileName)
            ? "Image unavailable"
            : $"{MediaFileName} unavailable";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed record ReactionAggregate(
    ReactionTargetKind TargetKind,
    string TargetId,
    string Emoji,
    int Count,
    bool MyReacted)
{
    public string Display => Count > 1 ? $"{Emoji} {Count}" : Emoji;
}

public sealed record ReactionChoice(ReactionTargetKind TargetKind, string TargetId, string Emoji);
