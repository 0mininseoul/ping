using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.App.Playback;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Ping.Windows.App.History;

public sealed partial class HistoryWindow : Window
{
    private const int VirtualKeyShift = 0x10;
    private readonly HistoryViewModel viewModel;
    private readonly Func<VideoMessage, CancellationToken, Task<string>> downloadVideoAsync;
    private readonly MessageService messageService;
    private readonly HistoryAutoRefreshCoordinator autoRefresh;
    private readonly List<PlaybackWindow> playbackWindows = [];
    private readonly string? initialRoomId;
    private readonly string? initialChatId;
    private string? selectedChatImagePath;
    private bool isApplyingSelection;

    public HistoryWindow(
        HistoryViewModel viewModel,
        Func<VideoMessage, CancellationToken, Task<string>> downloadVideoAsync,
        MessageService messageService,
        string? initialRoomId = null,
        string? initialChatId = null)
    {
        this.viewModel = viewModel;
        this.downloadVideoAsync = downloadVideoAsync;
        this.messageService = messageService;
        this.initialRoomId = initialRoomId;
        this.initialChatId = initialChatId;
        InitializeComponent();
        Root.DataContext = viewModel;
        autoRefresh = new HistoryAutoRefreshCoordinator(
            TimeSpan.FromSeconds(5),
            token => RunAsync(() => viewModel.LoadSelectedRoomAsync(token)));
        Root.Loaded += HandleLoaded;
        Closed += async (_, _) => await autoRefresh.StopAsync();
    }

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        var loaded = !string.IsNullOrWhiteSpace(initialRoomId) && !string.IsNullOrWhiteSpace(initialChatId)
            ? await RunAsync(() => viewModel.FocusChatAsync(initialRoomId, initialChatId))
            : await RunAsync(() => viewModel.LoadAsync(initialRoomId));
        if (loaded)
        {
            ApplySelectionFromViewModel();
            autoRefresh.Start();
        }
    }

    public async Task FocusRoomAsync(string roomId)
    {
        if (await RunAsync(() => viewModel.SelectRoomAsync(roomId)))
        {
            ApplySelectionFromViewModel();
        }
    }

    public async Task FocusChatAsync(string roomId, string chatId)
    {
        if (await RunAsync(() => viewModel.FocusChatAsync(roomId, chatId)))
        {
            ApplySelectionFromViewModel();
        }
    }

    private async void RoomsList_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (isApplyingSelection)
        {
            return;
        }

        viewModel.SelectedRoom = RoomsList.SelectedItem as Room;
        if (await RunAsync(() => viewModel.LoadSelectedRoomAsync()))
        {
            ApplySelectionFromViewModel();
        }
    }

    private void VideosList_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (isApplyingSelection)
        {
            return;
        }

        viewModel.SelectedTimelineItem = VideosList.SelectedItem as TimelineHistoryItem;
        viewModel.SelectedVideo = VideosList.SelectedItem switch
        {
            VideoHistoryItem item => item,
            TimelineHistoryItem { Video: { } video } => video,
            _ => null
        };
    }

    private async void PlayVideoButton_Click(object sender, RoutedEventArgs args)
    {
        if (viewModel.SelectedVideo?.Message is not { } video)
        {
            return;
        }

        await PlayVideoAsync(video);
    }

    private async void PlayVideoItemButton_Click(object sender, RoutedEventArgs args)
    {
        if (VideoItem(sender) is not { } item)
        {
            return;
        }

        viewModel.SelectedVideo = item;
        await PlayVideoAsync(item.Message);
    }

    private async void VideosList_DoubleTapped(object sender, DoubleTappedRoutedEventArgs args)
    {
        if (IsWithinButton(args.OriginalSource))
        {
            return;
        }

        if (viewModel.SelectedVideo?.Message is not { } video)
        {
            return;
        }

        await PlayVideoAsync(video);
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs args) =>
        await RefreshAndSyncSelectionAsync();

    private async void SendChatButton_Click(object sender, RoutedEventArgs args)
    {
        await SendChatFromComposerAsync();
    }

    private async void ChatBox_KeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key != Windows.System.VirtualKey.Enter || IsShiftDown())
        {
            return;
        }

        args.Handled = true;
        await SendChatFromComposerAsync();
    }

    private void ReplyVideoButton_Click(object sender, RoutedEventArgs args)
    {
        if (VideoItem(sender) is { } item)
        {
            viewModel.BeginReplyToVideo(item);
        }
    }

    private async void DeleteVideoButton_Click(object sender, RoutedEventArgs args)
    {
        if (VideoItem(sender) is { } item)
        {
            await RunAsync(() => viewModel.DeleteVideoAsync(item));
        }
    }

    private void ReplyChatButton_Click(object sender, RoutedEventArgs args)
    {
        if (ChatItem(sender) is { } item)
        {
            viewModel.BeginReplyToChat(item);
        }
    }

    private async void DeleteChatButton_Click(object sender, RoutedEventArgs args)
    {
        if (ChatItem(sender) is { } item)
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

    private async Task SendChatFromComposerAsync()
    {
        if (await RunAsync(() => viewModel.SendChatAsync(ChatBox.Text, selectedChatImagePath)))
        {
            ChatBox.Text = string.Empty;
            ClearSelectedImage();
        }
    }

    private async Task RefreshAndSyncSelectionAsync()
    {
        if (await RunAsync(() => autoRefresh.RefreshOnceAsync()))
        {
            ApplySelectionFromViewModel();
        }
    }

    private void ApplySelectionFromViewModel()
    {
        isApplyingSelection = true;
        try
        {
            RoomsList.SelectedItem = viewModel.SelectedRoom;
            VideosList.SelectedItem = viewModel.SelectedTimelineItem;
            if (viewModel.SelectedTimelineItem is not null)
            {
                VideosList.ScrollIntoView(viewModel.SelectedTimelineItem);
            }
        }
        finally
        {
            isApplyingSelection = false;
        }
    }

    private async Task PlayVideoAsync(VideoMessage video)
    {
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

    private static VideoHistoryItem? VideoItem(object sender) =>
        (sender as FrameworkElement)?.DataContext switch
        {
            VideoHistoryItem item => item,
            TimelineHistoryItem { Video: { } video } => video,
            _ => null
        };

    private static ChatHistoryItem? ChatItem(object sender) =>
        (sender as FrameworkElement)?.DataContext switch
        {
            ChatHistoryItem item => item,
            TimelineHistoryItem { Chat: { } chat } => chat,
            _ => null
        };

    private static bool IsWithinButton(object? source)
    {
        var current = source as DependencyObject;
        while (current is not null)
        {
            if (current is Button)
            {
                return true;
            }

            current = VisualTreeHelper.GetParent(current);
        }

        return false;
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

    private static bool IsShiftDown() =>
        (GetKeyState(VirtualKeyShift) & 0x8000) != 0;

    [DllImport("user32.dll")]
    private static extern short GetKeyState(int virtualKey);
}
