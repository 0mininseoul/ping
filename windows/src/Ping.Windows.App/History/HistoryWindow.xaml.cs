using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.App.Playback;
using Ping.Windows.App.UI;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Windows.System;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Ping.Windows.App.History;

public sealed partial class HistoryWindow : UserControl
{
    private const int VirtualKeyShift = 0x10;
    private readonly HistoryViewModel viewModel;
    private readonly Window owner;
    private bool backendReady;
    private bool detached;
    private readonly bool loadOnFirstLoaded;
    private bool isComposing;
    private bool ignoreCurrentEnter;
    public event EventHandler? RoomsRequested;
    public event EventHandler? FacePingRequested;
    public event EventHandler? ScreenPingRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? RetryRequested;
    private readonly Func<VideoMessage, CancellationToken, Task<string>> downloadVideoAsync;
    private readonly Func<VideoMessage, CancellationToken, Task> saveVideoAsync;
    private readonly MessageService messageService;
    private readonly HistoryAutoRefreshCoordinator autoRefresh;
    private readonly UiTaskDispatcher uiDispatcher;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer removalPermissionTimer;
    private readonly List<PlaybackWindow> playbackWindows = [];
    private readonly Func<VideoMessage, CancellationToken, Task>? playVideoAsync;
    private string? initialRoomId;
    private string? initialChatId;
    private bool isApplyingSelection;
    private string? lastScrolledRoomId;
    private TimelineHistoryItem? pendingScrollItem;
    private double? pendingScrollOffset;

    public HistoryWindow(
        Window owner,
        HistoryViewModel viewModel,
        Func<VideoMessage, CancellationToken, Task<string>> downloadVideoAsync,
        Func<VideoMessage, CancellationToken, Task> saveVideoAsync,
        MessageService messageService,
        string? initialRoomId = null,
        string? initialChatId = null,
        bool loadOnStart = true,
        TimeSpan? refreshInterval = null,
        Func<VideoMessage, CancellationToken, Task>? playVideoAsync = null)
    {
        this.owner = owner;
        this.playVideoAsync = playVideoAsync;
        backendReady = loadOnStart;
        loadOnFirstLoaded = loadOnStart;
        this.viewModel = viewModel;
        this.downloadVideoAsync = downloadVideoAsync;
        this.saveVideoAsync = saveVideoAsync;
        this.messageService = messageService;
        this.initialRoomId = initialRoomId;
        this.initialChatId = initialChatId;
        InitializeComponent();
        uiDispatcher = new UiTaskDispatcher(() => DispatcherQueue.HasThreadAccess, action => DispatcherQueue.TryEnqueue(() => action()));
        Root.DataContext = viewModel;
        VideosList.LayoutUpdated += (_, _) =>
        {
            if (VideosList.ActualHeight <= 0 || VideosList.Visibility != Visibility.Visible) return;
            if (pendingScrollItem is { } target)
            {
                pendingScrollItem = null;
                pendingScrollOffset = null;
                if (viewModel.Timeline.Contains(target)) VideosList.ScrollIntoView(target);
            }
            else if (pendingScrollOffset is { } offset && FindVisualChild<ScrollViewer>(VideosList) is { } scroll)
            {
                pendingScrollOffset = null;
                scroll.ChangeView(null, Math.Min(offset, scroll.ScrollableHeight), null, true);
            }
        };
        viewModel.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName is nameof(HistoryViewModel.SelectedRoom) or nameof(HistoryViewModel.DraftImagePath)) UpdateEmptyState();
        };
        viewModel.Timeline.CollectionChanged += (_, _) => UpdateEmptyState();
        removalPermissionTimer = DispatcherQueue.CreateTimer();
        removalPermissionTimer.Interval = TimeSpan.FromSeconds(1);
        removalPermissionTimer.Tick += (_, _) => viewModel.RefreshRemovalPermissions();
        removalPermissionTimer.Start();
        autoRefresh = new HistoryAutoRefreshCoordinator(
            refreshInterval ?? TimeSpan.FromSeconds(30),
            token => RunAsync(async () =>
            {
                if (!backendReady || !IsWindowVisible(WindowNative.GetWindowHandle(owner))) return;
                await viewModel.LoadSelectedRoomAsync(token);
            }));
        Root.Loaded += HandleLoaded;
        owner.Closed += HandleOwnerClosed;
        owner.Activated += HandleOwnerActivated;
    }

    private async void HandleOwnerClosed(object sender, WindowEventArgs args)
    {
        if (!args.Handled) await DetachAsync();
    }
    private async void HandleOwnerActivated(object sender, WindowActivatedEventArgs args)
    {
        if (!detached && backendReady && args.WindowActivationState != WindowActivationState.Deactivated) await RefreshNowAsync();
    }
    public async Task DetachAsync()
    {
        detached = true; backendReady = false; IsEnabled = false;
        owner.Closed -= HandleOwnerClosed; owner.Activated -= HandleOwnerActivated;
        Root.Loaded -= HandleLoaded;
        removalPermissionTimer.Stop();
        foreach (var window in playbackWindows.ToArray()) window.Close();
        await autoRefresh.StopAsync();
    }

    private async void HandleLoaded(object sender, RoutedEventArgs args)
    {
        UpdateEmptyState();
        if (!loadOnFirstLoaded) return;
        await ReloadRoomsAsync();
    }

    public async Task ReloadRoomsAsync()
    {
        backendReady = true;
        var roomId = initialRoomId;
        var chatId = initialChatId;
        initialRoomId = null;
        initialChatId = null;
        var loaded = !string.IsNullOrWhiteSpace(roomId) && !string.IsNullOrWhiteSpace(chatId)
            ? await RunAsync(() => viewModel.FocusChatAsync(roomId, chatId))
            : await RunAsync(() => viewModel.LoadAsync(roomId));
        if (loaded)
        {
            ApplySelectionFromViewModel();
            autoRefresh.Start();
        }
    }

    public async Task FocusRoomAsync(string roomId)
    {
        if (!backendReady) { initialRoomId = roomId; initialChatId = null; return; }
        if (await RunAsync(() => viewModel.SelectRoomAsync(roomId)))
        {
            ApplySelectionFromViewModel();
        }
    }

    public async Task FocusChatAsync(string roomId, string chatId)
    {
        if (!backendReady) { initialRoomId = roomId; initialChatId = chatId; return; }
        if (await RunAsync(() => viewModel.FocusChatAsync(roomId, chatId)))
        {
            ApplySelectionFromViewModel();
        }
    }

    private async void RoomsList_SelectionChanged(object sender, SelectionChangedEventArgs args)
    {
        if (isApplyingSelection || args.AddedItems.Count == 0)
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
        if (isApplyingSelection || args.AddedItems.Count == 0)
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
        await RefreshNowAsync();

    public async Task RefreshNowAsync(CancellationToken cancellationToken = default)
    {
        if (await RunAsync(() => autoRefresh.RefreshOnceAsync(cancellationToken)))
        {
            ApplySelectionFromViewModel();
        }
    }

    public async Task ApplyIncomingRoomsAsync(IReadOnlyList<Room> rooms, CancellationToken token)
    {
        if (!backendReady || token.IsCancellationRequested) return;
        isApplyingSelection = true;
        try { viewModel.ApplyRoomMetadata(rooms); ApplySelectionFromViewModel(); }
        finally { isApplyingSelection = false; }
        if (IsWindowVisible(WindowNative.GetWindowHandle(owner))) await RefreshNowAsync(token);
    }

    public bool IsViewingRoom(string roomId) =>
        string.Equals(viewModel.SelectedRoom?.Id, roomId, StringComparison.Ordinal)
        && IsWindowVisible(WindowNative.GetWindowHandle(owner))
        && GetForegroundWindow() == WindowNative.GetWindowHandle(owner);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr hwnd);

    public void Activate() => (owner as MainWindow)?.ShowShell();
    public void ReportConnectionStatus(string? status, bool canRetry = false)
    {
        ConnectionText.Text = status ?? "";
        ConnectionBanner.Visibility = string.IsNullOrWhiteSpace(status) ? Visibility.Collapsed : Visibility.Visible;
        RetryButton.Visibility = canRetry ? Visibility.Visible : Visibility.Collapsed;
    }
    public void SetHotkeyStatus(string message) => ToolTipService.SetToolTip(HotkeyHint, message);
    public void SetDefaultRoom(string name) => DefaultRoomText.Text = name;
    private void OpenRooms_Click(object sender, RoutedEventArgs args) => RoomsRequested?.Invoke(this, EventArgs.Empty);
    private void FacePing_Click(object sender, RoutedEventArgs args) => FacePingRequested?.Invoke(this, EventArgs.Empty);
    private void ScreenPing_Click(object sender, RoutedEventArgs args) => ScreenPingRequested?.Invoke(this, EventArgs.Empty);
    private void OpenSettings_Click(object sender, RoutedEventArgs args) => SettingsRequested?.Invoke(this, EventArgs.Empty);
    private void Retry_Click(object sender, RoutedEventArgs args) => RetryRequested?.Invoke(this, EventArgs.Empty);
    private void UpdateEmptyState()
    {
        var noRoom = viewModel.SelectedRoom is null;
        EmptyTitle.Text = noRoom ? "대화를 시작하세요" : "아직 메시지가 없어요";
        EmptyDetail.Text = noRoom ? "방을 만들거나 참여한 뒤 메시지와 3초 영상을 주고받으세요." : "아래에서 첫 메시지를 보내거나 얼굴 핑으로 인사를 건네보세요.";
        EmptyRoomButton.Visibility = noRoom ? Visibility.Visible : Visibility.Collapsed;
        EmptyState.Visibility = noRoom || viewModel.Timeline.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        AttachmentPreview.Visibility = viewModel.DraftImagePath is null ? Visibility.Collapsed : Visibility.Visible;
    }
    private void ChatCompositionStarted(TextBox sender, TextCompositionStartedEventArgs args) => isComposing = true;
    private void ChatCompositionEnded(TextBox sender, TextCompositionEndedEventArgs args)
    {
        ignoreCurrentEnter = (GetKeyState(0x0D) & 0x8000) != 0;
        isComposing = false;
    }
    private void ChatBox_KeyUp(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Enter) ignoreCurrentEnter = false;
    }

    private async void SendChatButton_Click(object sender, RoutedEventArgs args)
    {
        await SendChatFromComposerAsync();
    }

    private async void ChatBox_KeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key != global::Windows.System.VirtualKey.Enter || !ComposerKeyPolicy.ShouldSubmitEnter(isComposing || ignoreCurrentEnter, IsShiftDown()))
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

    private async void SaveVideoButton_Click(object sender, RoutedEventArgs args)
    {
        if (VideoItem(sender) is { } item)
        {
            await RunAsync(() => viewModel.SaveVideoAsync(item, saveVideoAsync));
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

    private async void OpenChatLinkButton_Click(object sender, RoutedEventArgs args)
    {
        if (ChatItem(sender)?.LinkPreviewUrl is { } url)
        {
            await Launcher.LaunchUriAsync(url);
        }
    }

    private void CancelReplyButton_Click(object sender, RoutedEventArgs args)
    {
        viewModel.CancelReply();
    }

    private async void AttachImageButton_Click(object sender, RoutedEventArgs args)
    {
        var picker = new FileOpenPicker();
        var hwnd = WindowNative.GetWindowHandle(owner);
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

        viewModel.DraftImagePath = file.Path;
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
        viewModel.DraftImagePath = null;
    }

    private async Task SendChatFromComposerAsync()
    {
        var sentRoomId = viewModel.SelectedRoom?.Id;
        var outcome = ChatSendOutcome.NoContent;
        await RunAsync(async () => { outcome = await viewModel.SendFromComposerAsync(); });
        if (outcome == ChatSendOutcome.Sent && viewModel.SelectedRoom?.Id == sentRoomId)
        {
            pendingScrollItem = viewModel.Timeline.LastOrDefault();
            VideosList.InvalidateMeasure();
        }
    }

    private void ApplySelectionFromViewModel()
    {
        isApplyingSelection = true;
        try
        {
            RoomsList.SelectedItem = viewModel.SelectedRoom;
            VideosList.SelectedItem = viewModel.SelectedTimelineItem;
            var currentRoomId = viewModel.SelectedRoom?.Id;
            if (viewModel.SelectedTimelineItem is not null)
            {
                pendingScrollItem = viewModel.SelectedTimelineItem;
            }
            else if (currentRoomId is not null && currentRoomId != lastScrolledRoomId)
            {
                // First time entering this room with no specific selection:
                // jump straight to the newest message (bottom), no animation.
                var newest = viewModel.Timeline.LastOrDefault();
                if (newest is not null)
                {
                    // Bindings can make the list visible after this callback. Wait for
                    // its measured layout before asking the ScrollViewer to reveal it.
                    pendingScrollItem = newest;
                }
            }
            if (currentRoomId is not null)
            {
                lastScrolledRoomId = currentRoomId;
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
            if (playVideoAsync is not null)
            {
                await playVideoAsync(video, CancellationToken.None);
                return;
            }
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

    private void VideoThumbnail_Loaded(object sender, RoutedEventArgs args) => ClipVideoThumbnail(sender);
    private void VideoThumbnail_SizeChanged(object sender, SizeChangedEventArgs args) => ClipVideoThumbnail(sender);
    private static void ClipVideoThumbnail(object sender)
    {
        if (sender is not FrameworkElement element || element.DataContext is not TimelineHistoryItem { Video: { } video }) return;
        RoundedCompositionClip.Apply(element, element.ActualWidth, element.ActualHeight,
            video.CaptureMode == CaptureMode.FaceOnly ? element.ActualWidth / 2 : 8);
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

    private void MessageMenu_Opening(object sender, object args)
    {
        if (sender is not MenuFlyout menu) return;
        AssignMenuContext(menu.Items, menu.Target?.DataContext);
    }
    private static void AssignMenuContext(IEnumerable<MenuFlyoutItemBase> items, object? context)
    {
        foreach (var item in items)
        {
            item.DataContext = context;
            if (item is MenuFlyoutSubItem sub) AssignMenuContext(sub.Items, context);
        }
    }
    private async void ContextReaction_Click(object sender, RoutedEventArgs args)
    {
        if (sender is not MenuFlyoutItem { Tag: string emoji } item) return;
        var video = VideoItem(item);
        var chat = ChatItem(item);
        await RunAsync(() => viewModel.ToggleReactionAsync(video is not null ? ReactionTargetKind.Video : ReactionTargetKind.Chat,
            video?.Message.Id ?? chat?.Message.Id, emoji));
    }
    private void CopyChat_Click(object sender, RoutedEventArgs args)
    {
        if (ChatItem(sender) is not { } item) return;
        var data = new global::Windows.ApplicationModel.DataTransfer.DataPackage();
        data.SetText(item.Body);
        global::Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(data);
    }
    private async void Timeline_KeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (args.Key == VirtualKey.Enter && viewModel.SelectedVideo is { } video)
        {
            args.Handled = true;
            await PlayVideoAsync(video.Message);
        }
        else if (args.Key == VirtualKey.Escape) ChatBox.Focus(FocusState.Keyboard);
    }

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

    private static T? FindVisualChild<T>(DependencyObject root) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match) return match;
            if (FindVisualChild<T>(child) is { } nested) return nested;
        }
        return null;
    }

    private Task<bool> RunAsync(Func<Task> work) => uiDispatcher.RunAsync(() => RunOnUiAsync(work));

    private async Task<bool> RunOnUiAsync(Func<Task> work)
    {
        if (detached) return false;
        try
        {
            var roomId = viewModel.SelectedRoom?.Id;
            var previousLast = viewModel.Timeline.LastOrDefault();
            var scroll = roomId == lastScrolledRoomId ? FindVisualChild<ScrollViewer>(VideosList) : null;
            var offset = scroll?.VerticalOffset;
            var followNewest = scroll is not null && scroll.ScrollableHeight - scroll.VerticalOffset <= 2;
            await work();
            if (detached) return false;
            if (offset is not null && viewModel.SelectedRoom?.Id == roomId
                && !ReferenceEquals(previousLast, viewModel.Timeline.LastOrDefault()))
            {
                if (followNewest) pendingScrollItem = viewModel.Timeline.LastOrDefault();
                else pendingScrollOffset = offset;
                VideosList.InvalidateMeasure();
            }
            return true;
        }
        catch (Exception ex)
        {
            if (detached) return false;
            viewModel.ReportError(ex);
            ReportConnectionStatus(ex.Message, canRetry: true);
            return false;
        }
    }

    private static bool IsShiftDown() =>
        (GetKeyState(VirtualKeyShift) & 0x8000) != 0;

    [DllImport("user32.dll")]
    private static extern short GetKeyState(int virtualKey);
}
