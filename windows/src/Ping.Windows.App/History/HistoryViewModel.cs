using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

#if WINDOWS
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Ping.Windows.App.Playback;
#endif

namespace Ping.Windows.App.History;

public sealed class HistoryViewModel : INotifyPropertyChanged
{
    private readonly RoomService roomService;
    private readonly MessageService messageService;
    private readonly ChatMessageService chatService;
    private readonly ReactionService reactionService;
    private Room? selectedRoom;
    private VideoMessage? selectedVideo;
    private string statusMessage = "History";

    public HistoryViewModel(
        RoomService roomService,
        MessageService messageService,
        ChatMessageService chatService,
        ReactionService reactionService)
    {
        this.roomService = roomService;
        this.messageService = messageService;
        this.chatService = chatService;
        this.reactionService = reactionService;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<Room> Rooms { get; } = [];

    public ObservableCollection<VideoMessage> Videos { get; } = [];

    public ObservableCollection<ChatMessage> Chats { get; } = [];

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

    public VideoMessage? SelectedVideo
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

    public async Task LoadAsync(CancellationToken cancellationToken = default)
    {
        Rooms.Clear();
        foreach (var room in (await roomService.MyRoomsAsync(cancellationToken)).OrderBy(room => room.Name, StringComparer.OrdinalIgnoreCase))
        {
            Rooms.Add(room);
        }

        SelectedRoom = Rooms.FirstOrDefault();
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
        foreach (var video in videos)
        {
            Videos.Add(video);
        }

        var chats = await chatService.RoomChatMessagesAsync(roomId, cancellationToken: cancellationToken);
        foreach (var chat in chats)
        {
            Chats.Add(chat);
        }

        var reactions = await reactionService.ReactionsAsync(
            chats.Where(chat => chat.Id is not null).Select(chat => chat.Id!).ToArray(),
            videos.Where(video => video.Id is not null).Select(video => video.Id!).ToArray(),
            cancellationToken);
        foreach (var reaction in reactions)
        {
            Reactions.Add(reaction);
        }

        StatusMessage = $"{Videos.Count} videos, {Chats.Count} chats, {Reactions.Count} reactions.";
    }

    public async Task SendChatAsync(string body, CancellationToken cancellationToken = default)
    {
        if (SelectedRoom?.Id is not { } roomId || string.IsNullOrWhiteSpace(body))
        {
            return;
        }

        await chatService.SendChatAsync(roomId, body.Trim(), cancellationToken: cancellationToken);
        await LoadSelectedRoomAsync(cancellationToken);
        StatusMessage = "Chat sent.";
    }

    public void ReportError(Exception exception)
    {
        StatusMessage = exception.Message;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

#if WINDOWS
public sealed partial class HistoryWindow : Window
{
    private readonly HistoryViewModel viewModel;
    private readonly Func<VideoMessage, CancellationToken, Task<string>> downloadVideoAsync;
    private readonly MessageService messageService;
    private readonly List<PlaybackWindow> playbackWindows = [];

    public HistoryWindow(
        HistoryViewModel viewModel,
        Func<VideoMessage, CancellationToken, Task<string>> downloadVideoAsync,
        MessageService messageService)
    {
        this.viewModel = viewModel;
        this.downloadVideoAsync = downloadVideoAsync;
        this.messageService = messageService;
        InitializeComponent();
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
    }

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        await RunAsync(() => viewModel.LoadAsync());
    }

    private async void RoomsList_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        viewModel.SelectedRoom = RoomsList.SelectedItem as Room;
        await RunAsync(() => viewModel.LoadSelectedRoomAsync());
    }

    private void VideosList_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        viewModel.SelectedVideo = VideosList.SelectedItem as VideoMessage;
    }

    private async void PlayVideoButton_Click(object sender, RoutedEventArgs args)
    {
        if (viewModel.SelectedVideo is not { } video)
        {
            return;
        }

        await RunAsync(async () =>
        {
            var localPath = await downloadVideoAsync(video, CancellationToken.None);
            var playback = new PlaybackWindow(new PlaybackViewModel(
                video,
                localPath,
                token => video.Id is null ? Task.CompletedTask : messageService.MarkSeenAsync(video.Id, token)));
            playback.Closed += (_, _) => playbackWindows.Remove(playback);
            playbackWindows.Add(playback);
            playback.Activate();
        });
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs args) =>
        await RunAsync(() => viewModel.LoadSelectedRoomAsync());

    private async void SendChatButton_Click(object sender, RoutedEventArgs args)
    {
        if (await RunAsync(() => viewModel.SendChatAsync(ChatBox.Text)))
        {
            ChatBox.Text = string.Empty;
        }
    }

    private async Task<bool> RunAsync(Func<Task> work)
    {
        try
        {
            await work();
            return true;
        }
        catch (Exception ex)
        {
            viewModel.ReportError(ex);
            return false;
        }
    }
}
#endif
