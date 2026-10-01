#if PING_UI_SMOKE
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Ping.Windows.App.Capture;
using Ping.Windows.App.History;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using global::Windows.Graphics.Imaging;
using global::Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

internal static class UiSmokeRunner
{
    public static string? OutputDirectory { get; set; }
    private static readonly List<string> Checks = [];
    private static bool failureWritten;
    private static void Step(string text) => File.AppendAllText(Path.Combine(OutputDirectory!, "phases.txt"), text + Environment.NewLine);
    private static void Check(bool condition, string label)
    {
        if (!condition) throw new InvalidOperationException(label);
        Checks.Add(label);
        Step("PASS " + label);
    }

    public static async Task RunAsync(App app)
    {
        Directory.CreateDirectory(OutputDirectory!);
        app.UnhandledException += (_, args) =>
        {
            WriteFailure(args.Exception);
            args.Handled = true;
            app.Exit();
        };
        MainWindow? window = null;
        try
        {
            Step("Creating isolated fixture services — no SupabaseClient, user files, tray or camera.");
            var rpc = new FixtureRpc();
            var storage = new FixtureStorage();
            var vm = new HistoryViewModel(new RoomService(rpc), new MessageService(rpc, storage), new ChatMessageService(rpc),
                new ReactionService(rpc), storage, () => "me", new FixtureLinks(), _ => rpc.AllowRead);
            window = new MainWindow();
            window.InitializeTrayWindowBehavior();
            var shell = new HistoryWindow(window, vm, (_, _) => throw new NotSupportedException("No camera/video fixture"),
                (_, _) => Task.CompletedTask, new MessageService(rpc, storage), loadOnStart: false, refreshInterval: TimeSpan.FromSeconds(5));
            window.AttachMessenger(shell);
            shell.SetDefaultRoom("디자인 이야기");
            window.ShowShell();
            Step("Main messenger created.");
            await shell.ReloadRoomsAsync();
            await Task.Delay(350);
            var root = (FrameworkElement)window.Content;
            Check(root.ActualWidth > 700 && root.ActualHeight > 500, "real main window has usable client area");
            Check(vm.Rooms.Count == 2 && vm.Timeline.Count == 4, "fixture rooms and mixed timeline loaded");
            Check(window.Content is ContentControl { Content: HistoryWindow }, "single main window hosts messenger control");
            var timelineScroll = Descendants((ListView)shell.FindName("VideosList")).OfType<ScrollViewer>().First();
            Step($"Initial timeline: offset={timelineScroll.VerticalOffset}, scrollable={timelineScroll.ScrollableHeight}, viewport={timelineScroll.ViewportHeight}");
            Check(timelineScroll.ScrollableHeight == 0 || timelineScroll.VerticalOffset >= timelineScroll.ScrollableHeight - 2,
                "opening a room shows its newest message");
            shell.RequestedTheme = ElementTheme.Light;
            await Task.Delay(180);
            await RenderAsync(root, "messenger-light.png");
            shell.RequestedTheme = ElementTheme.Dark;
            await Task.Delay(180);
            await RenderAsync(root, "messenger-dark.png");

            var chatBox = (TextBox)shell.FindName("ChatBox");
            var roomsList = (ListView)shell.FindName("RoomsList");
            chatBox.Text = "보존할 초안 A";
            await Task.Delay(50);
            Check(vm.DraftText == chatBox.Text, "text binding updates real composer state");
            roomsList.SelectedItem = vm.Rooms.Single(room => room.Id == "b");
            await Task.Delay(150);
            Check(vm.SelectedRoom?.Id == "b" && vm.Timeline.Count == 0, "real room selection switches to empty room");
            Check(((FrameworkElement)shell.FindName("EmptyState")).Visibility == Visibility.Visible
                && ((FrameworkElement)shell.FindName("VideosList")).Visibility == Visibility.Collapsed, "empty room CTA is not covered by timeline");
            chatBox.Text = "새 초안 B";
            roomsList.SelectedItem = vm.Rooms.Single(room => room.Id == "a");
            await Task.Delay(150);
            Check(chatBox.Text == "보존할 초안 A", "real binding restores room A draft after switching back");

            var timeline = (ListView)shell.FindName("VideosList");
            var chatRow = vm.Timeline.Last(row => row.Chat is not null);
            timeline.ScrollIntoView(chatRow);
            await Task.Delay(150);
            var menuOwner = Descendants(timeline).OfType<StackPanel>()
                .First(panel => ReferenceEquals(panel.DataContext, chatRow) && panel.Visibility == Visibility.Visible && panel.ContextFlyout is MenuFlyout);
            var menu = (MenuFlyout)menuOwner.ContextFlyout;
            menu.ShowAt(menuOwner);
            await Task.Delay(100);
            var reply = menu.Items.OfType<MenuFlyoutItem>().Single(item => item.Text == "답장");
            Check(ReferenceEquals(reply.DataContext, chatRow), "context flyout keeps actual message identity");
            ((IInvokeProvider)new MenuFlyoutItemAutomationPeer(reply).GetPattern(PatternInterface.Invoke)).Invoke();
            await Task.Delay(100);
            Check(vm.ReplyTarget?.ChatId == chatRow.Chat!.Message.Id, "context reply invokes real event handler");
            menu.Hide();

            chatBox.Text = "스모크 전송";
            var sendButton = (Button)shell.FindName("SendButton");
            Check(sendButton.IsEnabled, "nonempty bound draft enables actual send button");
            ((IInvokeProvider)new ButtonAutomationPeer(sendButton).GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => rpc.Sent == 1 && !vm.IsSending);
            Check(chatBox.Text == "" && vm.ReplyTarget is null && rpc.Sent == 1, "successful send updates visible composer without duplicate RPC");
            await UntilAsync(() => timelineScroll.VerticalOffset >= timelineScroll.ScrollableHeight - 2);
            Check(timelineScroll.VerticalOffset >= timelineScroll.ScrollableHeight - 2, "sending keeps the newest message visible");
            var readingOffset = Math.Min(35, timelineScroll.ScrollableHeight);
            timelineScroll.ChangeView(null, readingOffset, null, true);
            await Task.Delay(80);
            await shell.RefreshNowAsync();
            await Task.Delay(120);
            Check(Math.Abs(timelineScroll.VerticalOffset - readingOffset) < 2, "refresh preserves a scrolled conversation viewport");
            Check(Descendants(roomsList).OfType<TextBlock>().Count(text => text.Text == "2명") == 2, "room member counts are visible in actual bindings");

            window.ReportStatus("오프라인입니다. 다시 연결하는 중…", true);
            await RenderAsync(root, "messenger-offline.png");
            Check(((FrameworkElement)shell.FindName("RetryButton")).Visibility == Visibility.Visible, "connection failure preserves conversation and exposes retry");
            window.ReportStatus(null);

            Step("Creating real secondary settings window.");
            ScreenFaceQuickSendSettings? savedSettings = null;
            var settingsVm = new SettingsWindowViewModel("민", HotkeyBinding.Defaults(), ScreenFaceQuickSendSettings.Default,
                value => savedSettings = value, () => { }, new FixtureStartup(), archiveRootPath: OutputDirectory,
                ensureArchiveFolders: () => { }, deleteExpiredArchiveFiles: () => { }, openArchiveFolder: _ => Task.FromResult(false));
            var settings = new SettingsWindow(settingsVm);
            settings.Activate();
            await Task.Delay(250);
            var autoPlayToggle = Descendants(settings.Content).OfType<ToggleSwitch>().Single(toggle => toggle.Header?.ToString() == "받은 영상 자동 재생");
            Check(autoPlayToggle.IsOn, "real autoplay control defaults on");
            autoPlayToggle.IsOn = false;
            await Task.Delay(50);
            Check(savedSettings is { AutoPlayIncoming: false } && !settingsVm.AutoPlayIncoming, "real autoplay binding persists off");
            await RenderAsync((FrameworkElement)settings.Content, "settings.png");
            settings.Close();
            Check(true, "real settings window created, rendered and closed without crash");
            Step("Verifying owned native playback with a synthetic clip.");
            await PlaybackSmoke.RunAsync(window, OutputDirectory!, Check, RenderAsync);
            await AutoReplySmoke.RunAsync(window, Check, RenderAsync);
            await CaptureLifetimeSmoke.RunAsync(Check);
            await CaptureMirrorReviewSmoke.RunAsync(OutputDirectory!, Check, RenderAsync);

            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
            window.Close();
            await Task.Delay(100);
            Check(!window.AppWindow.IsVisible, "window close hides instead of disposing messenger");
            rpc.IncludeHiddenArrival = true;
            var verifiedRead = false;
            rpc.AllowRead = true;
            rpc.OnMarkRead = () =>
            {
                if (verifiedRead) return;
                Check(vm.Timeline.Any(row => row.SortId == "while-hidden"), "read acknowledgement follows displayed hidden arrival");
                verifiedRead = true;
            };
            window.ShowShell();
            await UntilAsync(() => vm.Timeline.Any(row => row.SortId == "while-hidden") && verifiedRead);
            Check(window.AppWindow.IsVisible && hwnd == WinRT.Interop.WindowNative.GetWindowHandle(window), "reopening reuses original window and HWND");
            Check(vm.Timeline.Any(row => row.SortId == "while-hidden"), "foreground return refreshes hidden arrivals before read acknowledgement");
            var readsBeforeTimer = rpc.TimelineReads;
            rpc.RequireUiThread = true;
            await UntilAsync(() => rpc.TimelineReads > readsBeforeTimer, 6);
            Check(true, "real refresh timer updates snapshots on UI thread");
            shell.RequestedTheme = ElementTheme.Light;
            var scale = shell.XamlRoot.RasterizationScale;
            window.AppWindow.Resize(new((int)(760 * scale), (int)(540 * scale)));
            await Task.Delay(180);
            Check(chatBox.ActualWidth >= 180 && sendButton.ActualWidth > 20 && roomsList.ActualWidth >= 200,
                "minimum window size keeps room list and composer usable");
            await RenderAsync(root, "messenger-minimum.png");
            File.WriteAllText(Path.Combine(OutputDirectory!, "result.json"), JsonSerializer.Serialize(new { Success = true, Checks, FixtureOnly = true }, new JsonSerializerOptions { WriteIndented = true }));
            Step("DONE");
        }
        catch (Exception error) { WriteFailure(error); }
        finally { window?.CloseForQuit(); app.Exit(); }
    }

    private static void WriteFailure(Exception error)
    {
        Directory.CreateDirectory(OutputDirectory!);
        if (failureWritten) return;
        failureWritten = true;
        File.WriteAllText(Path.Combine(OutputDirectory!, "result.json"), JsonSerializer.Serialize(new { Success = false, Error = error.ToString(), Checks }, new JsonSerializerOptions { WriteIndented = true }));
        Step("FAILED " + error.GetType().Name);
    }

    private static async Task UntilAsync(Func<bool> condition, int timeoutSeconds = 3)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (!condition())
        {
            if (DateTime.UtcNow >= deadline) throw new TimeoutException("UI fixture action did not settle.");
            await Task.Delay(25);
        }
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            yield return child;
            foreach (var descendant in Descendants(child)) yield return descendant;
        }
    }

    private static async Task RenderAsync(FrameworkElement root, string name)
    {
        root.UpdateLayout();
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(root);
        Check(bitmap.PixelWidth > 0 && bitmap.PixelHeight > 0, "render " + name);
        var pixels = (await bitmap.GetPixelsAsync()).ToArray();
        var path = Path.Combine(OutputDirectory!, name);
        File.WriteAllBytes(path, []);
        var file = await StorageFile.GetFileFromPathAsync(path);
        using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, pixels);
        await encoder.FlushAsync();
    }

    private sealed class FixtureRpc : ISupabaseRpcClient
    {
        public int Sent;
        public int TimelineReads;
        public bool IncludeHiddenArrival;
        public bool RequireUiThread;
        public bool AllowRead;
        public Action? OnMarkRead;
        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (RequireUiThread && Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread() is null)
                throw new InvalidOperationException("Fixture RPC was invoked outside the owning UI thread.");
            if (function == "ping_room_chat_messages") Interlocked.Increment(ref TimelineReads);
            var room = body is RoomChatMessagesRpcBody chat ? chat.RoomUuid : body is RoomMessagesRpcBody video ? video.RoomUuid : "a";
            object result = function switch
            {
                "ping_my_rooms" => new[] { Room("a", "디자인 이야기", 3), Room("b", "오늘의 작은 순간", 0) },
                "ping_room_messages" => room == "a" ? new[] { Video() } : Array.Empty<VideoMessage>(),
                "ping_room_chat_messages" => room == "a" ? new[]
                {
                    Chat("c1", "peer", "안녕! Windows에서도 이제 가볍게 핑을 보낼 수 있겠네 😊", -3),
                    Chat("c2", "me", "응, 대화하면서 3초 얼굴 영상도 바로 보낼 수 있어.", -2),
                    Chat("c3", "peer", "좋아. 자세한 이야기는 여기에서 이어가자!", -1)
                }.Concat(IncludeHiddenArrival ? new[] { Chat("while-hidden", "peer", "다시 열면 바로 보여야 하는 메시지", 0) } : Array.Empty<ChatMessage>()).ToArray() : Array.Empty<ChatMessage>(),
                "ping_message_reactions" => Array.Empty<MessageReaction>(),
                _ => throw new NotSupportedException(function)
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }
        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function != "ping_send_chat") throw new NotSupportedException(function);
            Sent++;
            return Task.FromResult((T)(object)"fixture-sent-chat");
        }
        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            if (function == "ping_mark_room_read") OnMarkRead?.Invoke();
            return Task.CompletedTask;
        }
        private static Room Room(string id, string name, int unread) => new(id, name, name, "me", ["me", "peer"], new Dictionary<string, string> { ["me"] = "민", ["peer"] = "서연" }, RoomStatus.Open, UnreadCount: unread);
        private static ChatMessage Chat(string id, string sender, string text, int minutes) => new()
        { Id = id, RoomId = "a", SenderUid = sender, SenderNickname = sender == "me" ? "민" : "서연", Body = text, CreatedAt = DateTimeOffset.UtcNow.AddMinutes(minutes) };
        private static VideoMessage Video() => new()
        { Id = "v1", RoomId = "a", SenderUid = "peer", ReceiverUid = "me", SenderNickname = "서연", VideoId = "fixture", VideoUrl = "peer/fixture.mp4", DurationMs = 3000, MirrorPosition = new(0.5, 0.5), Status = MessageStatus.Uploaded, CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-4), ExpiresAt = DateTimeOffset.UtcNow.AddDays(1) };
    }
    private sealed class FixtureStorage : IStorageService, IChatMediaStorageService
    {
        public Task<string> UploadVideoAsync(string localVideoPath, string senderUid, string videoId, IReadOnlyCollection<string> authorizedReceiverUids, DateTimeOffset expiresAt, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task DeleteVideoAsync(string remotePath, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<ChatImageUpload> UploadChatImageAsync(string localImagePath, string senderUid, string messageId, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<string> DownloadChatMediaAsync(string remotePath, string fileExtension, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task DeleteChatMediaAsync(string remotePath, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
    private sealed class FixtureLinks : ILinkPreviewService
    {
        public Task<LinkPreviewMetadata> MetadataAsync(Uri url, CancellationToken cancellationToken = default) => Task.FromResult(LinkPreviewMetadata.Fallback(url));
    }
    private sealed class FixtureStartup : IStartupTaskController
    {
        public Task<PingStartupTaskStatus> GetStatusAsync(CancellationToken cancellationToken = default) => Task.FromResult(new PingStartupTaskStatus(PingStartupTaskState.Disabled, "Fixture startup disabled"));
        public Task<PingStartupTaskStatus> SetEnabledAsync(bool isEnabled, CancellationToken cancellationToken = default) => GetStatusAsync(cancellationToken);
    }
}
#endif
