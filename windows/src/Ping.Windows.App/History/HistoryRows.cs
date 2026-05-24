using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
#endif

namespace Ping.Windows.App.History;

public sealed class VideoHistoryItem
{
    public VideoHistoryItem(
        VideoMessage message,
        IReadOnlyCollection<string> quickReactions,
        IReadOnlyCollection<ReactionAggregate> reactions)
    {
        Message = message;
        Reactions = new ObservableCollection<ReactionAggregate>(reactions);
        QuickReactions = message.Id is null
            ? []
            : quickReactions.Select(emoji => new ReactionChoice(ReactionTargetKind.Video, message.Id, emoji)).ToArray();
    }

    public VideoMessage Message { get; }

    public ObservableCollection<ReactionAggregate> Reactions { get; }

    public IReadOnlyList<ReactionChoice> QuickReactions { get; }

    public string SenderNickname => Message.SenderNickname;

    public string VideoId => Message.VideoId;

    public CaptureMode CaptureMode => Message.CaptureMode;
}

public sealed class ChatHistoryItem : INotifyPropertyChanged
{
#if WINDOWS
    private BitmapImage? imageSource;
#else
    private Uri? imageSource;
#endif
    private string attachmentStatus;

    public ChatHistoryItem(
        ChatMessage message,
        IReadOnlyCollection<string> quickReactions,
        IReadOnlyCollection<ReactionAggregate> reactions)
    {
        Message = message;
        Reactions = new ObservableCollection<ReactionAggregate>(reactions);
        QuickReactions = message.Id is null
            ? []
            : quickReactions.Select(emoji => new ReactionChoice(ReactionTargetKind.Chat, message.Id, emoji)).ToArray();
        attachmentStatus = message.MediaFileName ?? (HasImageAttachment ? "Image attachment" : string.Empty);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ChatMessage Message { get; }

    public ObservableCollection<ReactionAggregate> Reactions { get; }

    public IReadOnlyList<ReactionChoice> QuickReactions { get; }

    public string SenderNickname => Message.SenderNickname;

    public string Body => Message.Body;

    public string MediaFileName => Message.MediaFileName ?? string.Empty;

    public bool HasImageAttachment => !string.IsNullOrWhiteSpace(Message.MediaPath);

#if WINDOWS
    public Visibility AttachmentVisibility => HasImageAttachment ? Visibility.Visible : Visibility.Collapsed;

    public Visibility ImageVisibility => imageSource is null ? Visibility.Collapsed : Visibility.Visible;

    public BitmapImage? ImageSource
#else
    public bool AttachmentVisibility => HasImageAttachment;

    public bool ImageVisibility => imageSource is not null;

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
