using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Ping.Windows.App.Playback;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Ping.Windows.App.History;

public sealed partial class HistoryWindow : Window
{
    private readonly HistoryViewModel viewModel;
    private readonly Func<VideoMessage, CancellationToken, Task<string>> downloadVideoAsync;
    private readonly MessageService messageService;
    private readonly List<PlaybackWindow> playbackWindows = [];
    private readonly string? initialRoomId;
    private string? selectedChatImagePath;

    public HistoryWindow(
        HistoryViewModel viewModel,
        Func<VideoMessage, CancellationToken, Task<string>> downloadVideoAsync,
        MessageService messageService,
        string? initialRoomId = null)
    {
        this.viewModel = viewModel;
        this.downloadVideoAsync = downloadVideoAsync;
        this.messageService = messageService;
        this.initialRoomId = initialRoomId;
        InitializeComponent();
        Root.DataContext = viewModel;
        Root.Loaded += HandleLoaded;
    }

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        await RunAsync(() => viewModel.LoadAsync(initialRoomId));
    }

    public async Task FocusRoomAsync(string roomId)
    {
        await RunAsync(() => viewModel.SelectRoomAsync(roomId));
    }

    private async void RoomsList_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        viewModel.SelectedRoom = RoomsList.SelectedItem as Room;
        await RunAsync(() => viewModel.LoadSelectedRoomAsync());
    }

    private void VideosList_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        viewModel.SelectedVideo = VideosList.SelectedItem as VideoHistoryItem;
    }

    private async void PlayVideoButton_Click(object sender, RoutedEventArgs args)
    {
        if (viewModel.SelectedVideo?.Message is not { } video)
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
        if (await RunAsync(() => viewModel.SendChatAsync(ChatBox.Text, selectedChatImagePath)))
        {
            ChatBox.Text = string.Empty;
            ClearSelectedImage();
        }
    }

    private void ReplyVideoButton_Click(object sender, RoutedEventArgs args)
    {
        if ((sender as FrameworkElement)?.DataContext is VideoHistoryItem item)
        {
            viewModel.BeginReplyToVideo(item);
        }
    }

    private async void DeleteVideoButton_Click(object sender, RoutedEventArgs args)
    {
        if ((sender as FrameworkElement)?.DataContext is VideoHistoryItem item)
        {
            await RunAsync(() => viewModel.DeleteVideoAsync(item));
        }
    }

    private void ReplyChatButton_Click(object sender, RoutedEventArgs args)
    {
        if ((sender as FrameworkElement)?.DataContext is ChatHistoryItem item)
        {
            viewModel.BeginReplyToChat(item);
        }
    }

    private async void DeleteChatButton_Click(object sender, RoutedEventArgs args)
    {
        if ((sender as FrameworkElement)?.DataContext is ChatHistoryItem item)
        {
            await RunAsync(() => viewModel.DeleteChatAsync(item));
        }
    }

    private void CancelReplyButton_Click(object sender, RoutedEventArgs args)
    {
        viewModel.CancelReply();
    }

    private async void AttachImageButton_Click(object sender, RoutedEventArgs args)
    {
        var picker = new FileOpenPicker();
        var hwnd = WindowNative.GetWindowHandle(this);
        InitializeWithWindow.Initialize(picker, hwnd);
        foreach (var extension in new[] { ".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".webp" })
        {
            picker.FileTypeFilter.Add(extension);
        }

        var file = await picker.PickSingleFileAsync();
        if (file is null)
        {
            return;
        }

        selectedChatImagePath = file.Path;
        SelectedImageText.Text = file.Name;
    }

    private void ClearImageButton_Click(object sender, RoutedEventArgs args)
    {
        ClearSelectedImage();
    }

    private async void ReactionButton_Click(object sender, RoutedEventArgs args)
    {
        switch ((sender as FrameworkElement)?.DataContext)
        {
            case ReactionChoice choice:
                await RunAsync(() => viewModel.ToggleReactionAsync(choice.TargetKind, choice.TargetId, choice.Emoji));
                break;
            case ReactionAggregate aggregate:
                await RunAsync(() => viewModel.ToggleReactionAsync(aggregate.TargetKind, aggregate.TargetId, aggregate.Emoji));
                break;
        }
    }

    private void ClearSelectedImage()
    {
        selectedChatImagePath = null;
        SelectedImageText.Text = string.Empty;
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
