using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
#endif

namespace Ping.Windows.App.History;

public sealed class TimelineHistoryItem : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private bool showsSender;
    public bool ShowsSender
    {
        get => showsSender;
        internal set { if (showsSender == value) return; showsSender = value; PropertyChanged?.Invoke(this, new(nameof(SenderVisibility))); }
    }
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
    public bool IsMine => Video?.IsMine ?? Chat?.IsMine ?? false;
    public string SenderLabel => Video?.SenderNickname ?? Chat?.SenderNickname ?? "";
    public string TimeLabel => CreatedAt?.ToLocalTime().ToString("HH:mm") ?? "";
    public string DayHeading { get; internal set; } = "";

#if WINDOWS
    public HorizontalAlignment BubbleAlignment => IsMine ? HorizontalAlignment.Right : HorizontalAlignment.Left;
    public Visibility SenderVisibility => ShowsSender && !IsMine ? Visibility.Visible : Visibility.Collapsed;
    public Visibility DayHeadingVisibility => string.IsNullOrEmpty(DayHeading) ? Visibility.Collapsed : Visibility.Visible;
    public Visibility VideoVisibility => Video is null ? Visibility.Collapsed : Visibility.Visible;

    public Visibility ChatVisibility => Chat is null ? Visibility.Collapsed : Visibility.Visible;
#else
    public bool SenderVisibility => ShowsSender && !IsMine;
    public bool DayHeadingVisibility => !string.IsNullOrEmpty(DayHeading);
    public bool VideoVisibility => Video is not null;

    public bool ChatVisibility => Chat is not null;
#endif
}

public sealed class VideoHistoryItem : INotifyPropertyChanged
{
    private bool isInlineExpanded;
    public bool IsInlineExpanded
    {
        get => isInlineExpanded;
        set { if (isInlineExpanded == value) return; isInlineExpanded = value; OnPropertyChanged(); OnPropertyChanged(nameof(InlineVisibility)); OnPropertyChanged(nameof(PreviewVisibility)); }
    }
#if WINDOWS
    public Visibility InlineVisibility => IsInlineExpanded ? Visibility.Visible : Visibility.Collapsed;
    public Visibility PreviewVisibility => IsInlineExpanded ? Visibility.Collapsed : Visibility.Visible;
#else
    public bool InlineVisibility => IsInlineExpanded;
    public bool PreviewVisibility => !IsInlineExpanded;
#endif
    private readonly string? currentUid;
    private readonly Func<DateTimeOffset> nowProvider;
#if WINDOWS
    private BitmapImage? thumbnailSource;
#else
    private Uri? thumbnailSource;
#endif

    public VideoHistoryItem(
        VideoMessage message,
        IReadOnlyCollection<string> quickReactions,
        IReadOnlyCollection<ReactionAggregate> reactions,
        string? currentUid = null,
        Func<DateTimeOffset>? nowProvider = null)
    {
        Message = message;
        this.currentUid = currentUid;
        this.nowProvider = nowProvider ?? (() => DateTimeOffset.UtcNow);
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
    public double ThumbnailWidth => CaptureMode == CaptureMode.FaceOnly ? 60 : 90;
    public double ThumbnailHeight => CaptureMode == CaptureMode.FaceOnly ? 60 : 90 / Math.Clamp(
        Message.AspectRatio is { } aspect && double.IsFinite(aspect) ? aspect : 1.78, 0.5, 3.0);
    public string ModeLabel => Message.CaptureMode == CaptureMode.ScreenFace ? "화면 + 얼굴" : "얼굴 핑";
    public string AutoReplyLabel => Message.IsAutoReply ? "자동 회신" : "";

    public bool IsMine { get; }

    public bool CanSave { get; }

    public MessageRemovalAction RemovalAction => MessageRemovalPolicy.ForVideo(Message.SenderUid, Message.ReceiverUid, Message.CreatedAt, currentUid, nowProvider());
    public string RemovalLabel => RemovalAction == MessageRemovalAction.Hide ? "나에게서 숨기기" : "모두에게서 삭제";
    public void RefreshRemovalPermission()
    {
        OnPropertyChanged(nameof(DeleteVisibility));
        OnPropertyChanged(nameof(RemovalLabel));
    }

    public event PropertyChangedEventHandler? PropertyChanged;

#if WINDOWS
    public Visibility DeleteVisibility => RemovalAction == MessageRemovalAction.None ? Visibility.Collapsed : Visibility.Visible;

    public Visibility SaveVisibility => CanSave ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ThumbnailVisibility => thumbnailSource is null ? Visibility.Collapsed : Visibility.Visible;

    public Visibility ThumbnailPlaceholderVisibility => thumbnailSource is null ? Visibility.Visible : Visibility.Collapsed;

    public BitmapImage? ThumbnailSource
#else
    public bool DeleteVisibility => RemovalAction != MessageRemovalAction.None;

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
    private readonly string? currentUid;
    private readonly Func<DateTimeOffset> nowProvider;
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
        string? replyPreview = null,
        Func<DateTimeOffset>? nowProvider = null)
    {
        Message = message;
        this.currentUid = currentUid;
        this.nowProvider = nowProvider ?? (() => DateTimeOffset.UtcNow);
        Reactions = new ObservableCollection<ReactionAggregate>(reactions);
        QuickReactions = message.Id is null
            ? []
            : quickReactions.Select(emoji => new ReactionChoice(ReactionTargetKind.Chat, message.Id, emoji)).ToArray();
        attachmentStatus = HasImageAttachment ? "사진을 불러오는 중…" : string.Empty;
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
    public bool CanPreviewImage => ImageSource is not null
#if WINDOWS
        && ImageSource.PixelWidth > 0 && ImageSource.PixelHeight > 0
#endif
        ;
    private (double Width, double Height) ImageSize
    {
        get
        {
            if (Message.MediaWidth is not > 0 || Message.MediaHeight is not > 0) return (200, 160);
            var scale = Math.Min(240d / Message.MediaWidth.Value, 260d / Message.MediaHeight.Value);
            return (Math.Max(80, Message.MediaWidth.Value * scale), Math.Max(80, Message.MediaHeight.Value * scale));
        }
    }
    public double ImageWidth => ImageSize.Width;
    public double ImageHeight => ImageSize.Height;

    public bool IsMine { get; }

    public bool CanDelete => MessageRemovalPolicy.CanDeleteChat(Message.SenderUid, Message.CreatedAt, currentUid, nowProvider());
    public void RefreshRemovalPermission() => OnPropertyChanged(nameof(DeleteVisibility));

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
    public Visibility BodyVisibility => string.IsNullOrWhiteSpace(Body) ? Visibility.Collapsed : Visibility.Visible;
    public Visibility AttachmentVisibility => HasImageAttachment ? Visibility.Visible : Visibility.Collapsed;

    public Visibility DeleteVisibility => CanDelete ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ImageVisibility => imageSource is null ? Visibility.Collapsed : Visibility.Visible;

    public Visibility ReplyPreviewVisibility => string.IsNullOrWhiteSpace(ReplyPreview) ? Visibility.Collapsed : Visibility.Visible;

    public Visibility LinkPreviewVisibility => LinkPreviewUrl is null ? Visibility.Collapsed : Visibility.Visible;

    public Visibility LinkPreviewSummaryVisibility => string.IsNullOrWhiteSpace(LinkPreviewSummary) ? Visibility.Collapsed : Visibility.Visible;

    public Visibility LinkPreviewImageVisibility => linkPreviewImageSource is null ? Visibility.Collapsed : Visibility.Visible;

    public BitmapImage? LinkPreviewImageSource => linkPreviewImageSource;

    public BitmapImage? ImageSource
#else
    public bool AttachmentVisibility => HasImageAttachment;

    public bool DeleteVisibility => CanDelete;

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
            OnPropertyChanged(nameof(CanPreviewImage));
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
        var bitmap = new BitmapImage(new Uri(Path.GetFullPath(localPath)));
        bitmap.ImageOpened += (_, _) => { if (ReferenceEquals(ImageSource, bitmap)) OnPropertyChanged(nameof(CanPreviewImage)); };
        bitmap.ImageFailed += (_, _) => { if (ReferenceEquals(ImageSource, bitmap)) SetAttachmentError(); };
        ImageSource = bitmap;
#else
        ImageSource = new Uri(Path.GetFullPath(localPath));
#endif
        AttachmentStatus = string.IsNullOrWhiteSpace(MediaFileName) ? "사진" : MediaFileName;
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
        AttachmentStatus = "사진을 불러올 수 없어요";
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
