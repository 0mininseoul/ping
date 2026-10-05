#if PING_UI_SMOKE
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Windows.AppNotifications;
using Ping.Windows.App.Bootstrap;
using Ping.Windows.App.Capture;
using Ping.Windows.App.History;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Notifications;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    private static async Task VerifyOwnedRuntimeAsync()
    {
        var options = OwnedLive!;
        var errors = new List<string>();
        var limitations = new List<string>();
        var notificationIds = new HashSet<uint>();
        var ownedVideoPaths = new List<string>();
        string? roomId = null;
        string? uidA = null;
        string? uidB = null;
        AppCoordinator? receiver = null;
        var phase = "guard";
        var lifetimeWindow = new MainWindow();
        lifetimeWindow.InitializeTrayWindowBehavior(); lifetimeWindow.ShowShell();
        MainWindow? receiverWindow = null;
        string Session(string name) => Path.Combine(options.Sessions, name, "SupabaseSession.json");
        using var httpA = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        using var a = new SupabaseClient(httpA, options.Config, Session("a"));
        try
        {
            Check(!IsPinnedOwnedConfiguration(new() { SupabaseUrl = "https://example.com", SupabaseUrlShort = "https://qxjtprxvjmaxlbtljcjw.supabase.co", SupabaseAnonKeyShort = "fixture" }), "mixed config aliases cannot bypass effective project guard");
            Check(!IsPinnedOwnedConfiguration(new() { SupabaseUrlShort = "http://qxjtprxvjmaxlbtljcjw.supabase.co", SupabaseAnonKeyShort = "fixture" }), "owned backend requires HTTPS");
            Check(IsPinnedOwnedConfigurationFile(options.Config), "runtime uses pinned effective Ping project");
            var storedA = await new SupabaseSessionStore(Session("a")).LoadAsync();
            var storedB = await new SupabaseSessionStore(Session("b")).LoadAsync();
            Check(storedA is not null && storedB is not null && storedA.UserId != storedB.UserId, "runtime requires existing distinct owned sessions before network");
            phase = "prepare owned room";
            uidA = await a.BootstrapAsync();
            using (var httpB = new HttpClient { Timeout = TimeSpan.FromSeconds(15) })
            using (var b = new SupabaseClient(httpB, options.Config, Session("b")))
            {
                uidB = await b.BootstrapAsync();
                Check(uidA == storedA!.UserId && uidB == storedB!.UserId, "runtime restores both existing identities");
                Check((await new RoomService(a).MyRoomsAsync()).Count == 0 && (await new RoomService(b).MyRoomsAsync()).Count == 0, "runtime requires empty owned room lists");
                var marker = "QA" + Guid.NewGuid().ToString("N")[..10];
                roomId = (await new RoomService(a).CreateRoomAsync(marker, "QA 민")).Id!;
                File.WriteAllText(Path.Combine(OutputDirectory!, "owned-room.json"), JsonSerializer.Serialize(new { roomId }));
                var invitation = await new InvitationService(a).SendAsync(uidB, roomId, "QA 민", marker);
                await new InvitationService(b).AcceptAsync(invitation, "QA 서연");
                var room = (await new RoomService(a).MyRoomsAsync()).Single(r => r.Id == roomId);
                Check(room.MemberUids.Count == 2 && room.MemberUids.Contains(uidA) && room.MemberUids.Contains(uidB), "runtime room contains only owned peers");
            }
            phase = "receiver startup";
            var runtimeRoot = Path.Combine(OutputDirectory!, "runtime");
            var scope = AppCoordinatorStorage.InDirectory(runtimeRoot);
            new ScreenFaceQuickSendSettingsStore(scope.QuickSendSettingsPath).Save(ScreenFaceQuickSendSettings.Default with
            {
                DefaultRoomId = roomId, NotificationSoundEnabled = false,
                Preferences = ScreenFaceQuickSendPreferences.Default with { SaveReceivedCopy = false }
            });
            receiverWindow = new MainWindow(); receiverWindow.InitializeTrayWindowBehavior(); receiverWindow.ShowShell();
            receiver = new(receiverWindow, new HotkeyPreferencesStore(runtimeRoot), new GlobalHotkeyManager(), null,
                new SupabaseClient(configPath: options.Config, sessionPath: Session("b")), scope, automaticCaptureAccess: () => false);
            receiver.Start();
            await UntilAsync(() => receiver.DiagnosticReady, 45);
            TestDisplayPlacement.Verify(receiverWindow, Check);
            Check(receiver.DiagnosticTrayVisible, "actual shell tray icon is registered");
            var notificationsRegistered = receiver.DiagnosticNotificationsRegistered;
            if (notificationsRegistered) Check(true, "actual Windows notifications are registered");
            else
            {
                limitations.Add("OS notifications unavailable in unpackaged diagnostic: " + receiver.DiagnosticNotificationFailure);
                limitations.Add("Automatic playback and OS duplicate suppression not verified; public video activation handler tested instead.");
                Step("UNVERIFIED OS notification registration and automatic playback");
            }
            var shell = Descendants((FrameworkElement)receiverWindow.Content).OfType<HistoryWindow>().Single();
            Check(receiverWindow.Content is ContentControl { Content: HistoryWindow }, "real coordinator hosts native messenger");
            var handle = WinRT.Interop.WindowNative.GetWindowHandle(receiverWindow);
            receiverWindow.Close(); await Task.Delay(100);
            Check(!receiverWindow.AppWindow.IsVisible && WinRT.Interop.WindowNative.GetWindowHandle(receiverWindow) == handle, "close hides messenger while retaining same native window");

            phase = "background chat";
            var body = "백그라운드 수신 · Pretendard 한글 🙂";
            var chatId = await new ChatMessageService(a).SendChatAsync(roomId, body);
            async Task<IReadOnlyList<AppNotification>> OwnedNotifications(string id)
            {
                if (!notificationsRegistered) return [];
                var all = await AppNotificationManager.Default.GetAllAsync();
                var owned = all.Where(n => n.Payload.Contains(id, StringComparison.Ordinal)).ToArray();
                foreach (var notification in owned) notificationIds.Add(notification.Id);
                return owned;
            }
            async Task WaitForNotification(string id)
            {
                if (!notificationsRegistered) return;
                var deadline = DateTimeOffset.UtcNow.AddSeconds(40);
                while ((await OwnedNotifications(id)).Count == 0 && DateTimeOffset.UtcNow < deadline) await Task.Delay(200);
                Check((await OwnedNotifications(id)).Count == 1, "OS queue contains one owned notification");
            }
            await WaitForNotification(chatId);
            receiver.HandleNotificationActivation(new("chat", null, chatId, roomId));
            await UntilAsync(() => receiverWindow.AppWindow.IsVisible && Descendants(shell).OfType<TextBlock>().Any(t => t.Name == "LinkedChatBody" && t.Text == body), 20);
            Check(WinRT.Interop.WindowNative.GetWindowHandle(receiverWindow) == handle, "public chat notification handler reopens same messenger with received text");
            TypographySmoke.Verify((FrameworkElement)receiverWindow.Content, Check);
            var videos = new MessageService(a, new StorageService(a));
            var roomForSend = (await new RoomService(a).MyRoomsAsync()).Single(r => r.Id == roomId);
            foreach (var mode in new[] { CaptureMode.FaceOnly, CaptureMode.ScreenFace })
            {
                phase = "receive " + mode;
                receiverWindow.Close();
                var videoId = Guid.NewGuid().ToString();
                ownedVideoPaths.Add($"{uidA}/{videoId}.mp4");
                File.WriteAllText(Path.Combine(OutputDirectory!, "owned-videos.json"), JsonSerializer.Serialize(new { roomId, paths = ownedVideoPaths }));
                await videos.SendAsync(new([roomForSend], Path.Combine(options.Fixtures, "owned-face-source.mp4"), new(0.25, 0.75), uidA, "QA 민", mode, 320d / 192, false, videoId));
                if (!notificationsRegistered)
                {
                    var received = (await videos.RoomMessagesAsync(roomId)).Single(v => v.VideoId == videoId && v.ReceiverUid == uidB);
                    receiver.HandleNotificationActivation(new("play", received.Id));
                }
                await UntilAsync(() => receiver.DiagnosticPlayers.Any(p => p.ViewModel.Message.VideoId == videoId), 40);
                var player = receiver.DiagnosticPlayers.Single(p => p.ViewModel.Message.VideoId == videoId);
                TestDisplayPlacement.Verify(player, Check);
                await UntilAsync(() => Descendants((FrameworkElement)player.Content).OfType<MediaPlayerElement>().Any(p => p.MediaPlayer?.PlaybackSession.NaturalVideoWidth == 320), 15);
                var deliveryLabel = (notificationsRegistered ? "automatic " : "public video activation ") + mode;
                Check(true, deliveryLabel + " player decodes owned private download");
                var messageId = player.ViewModel.Message.Id!;
                await WaitForNotification(messageId);
                var deadline = DateTimeOffset.UtcNow.AddSeconds(15);
                while ((await videos.GetAsync(messageId))?.Status != MessageStatus.Seen && DateTimeOffset.UtcNow < deadline) await Task.Delay(150);
                Check((await videos.GetAsync(messageId))?.Status == MessageStatus.Seen, deliveryLabel + " completion marks server seen");
                player.ViewModel.HandleEnter(); await Task.Delay(100);
                Check(receiver.DiagnosticPlayers.Count(p => p.ViewModel.Message.Id == messageId) == 1, "replay keeps one existing player");
                player.ViewModel.HandleEscape();
                await UntilAsync(() => receiver.DiagnosticPlayers.All(p => p.ViewModel.Message.Id != messageId), 5);
                if (notificationsRegistered) Check((await OwnedNotifications(messageId)).Count == 1, "replay does not duplicate OS notification");
            }
            phase = "tray reopen";
            receiver.Execute(HotkeyCommand.History);
            await UntilAsync(() => receiverWindow.AppWindow.IsVisible, 5);
            Check(WinRT.Interop.WindowNative.GetWindowHandle(receiverWindow) == handle && receiver.DiagnosticTrayVisible, "coordinator history entry reuses window and retains tray");
            shell.RequestedTheme = ElementTheme.Light; await Task.Delay(100); await RenderAsync(shell, "runtime-messenger-light.png");
            shell.RequestedTheme = ElementTheme.Dark; await Task.Delay(100); await RenderAsync(shell, "runtime-messenger-dark.png");
            Check(Directory.EnumerateFiles(runtimeRoot, "*.json", SearchOption.AllDirectories).Any(), "runtime state is written inside explicit owned root");
        }
        catch (Exception error) { errors.Add(phase + ": " + SafeLiveError(error)); }
        finally
        {
            var stopped = receiver is null;
            if (receiver is not null)
            {
                foreach (var id in notificationIds)
                {
                    try { await AppNotificationManager.Default.RemoveByIdAsync(id); }
                    catch (Exception error) { errors.Add("owned notification cleanup: " + SafeLiveError(error)); }
                }
                try
                {
                    await receiver.ShutdownForAccountChangeAsync(); stopped = true;
                    Check(receiver.IsDisposed && !receiver.DiagnosticTrayVisible, "receiver shutdown removes tray and completes backend tasks");
                }
                catch (Exception error) { errors.Add("receiver shutdown: " + SafeLiveError(error)); }
            }
            receiverWindow?.CloseForQuit();
            if (roomId is not null && stopped && uidA is not null && uidB is not null)
            {
                try
                {
                    using var httpB = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
                    using var b = new SupabaseClient(httpB, options.Config, Session("b"));
                    Check(await b.BootstrapAsync() == uidB, "cleanup restores latest retired receiver session");
                    var chats = new ChatMessageService(a);
                    foreach (var chat in await chats.RoomChatMessagesAsync(roomId))
                    {
                        if (chat.SenderUid != uidA || chat.MediaPath is not null) throw new InvalidOperationException("unexpected owned room chat");
                        await chats.DeleteChatAsync(chat.Id!);
                    }
                    var storage = new StorageService(a); var videos = new MessageService(a, storage);
                    foreach (var video in await videos.RoomMessagesAsync(roomId))
                    {
                        if (video.SenderUid != uidA || !ownedVideoPaths.Contains(video.VideoUrl)) throw new InvalidOperationException("unexpected owned room video");
                        await videos.DeleteMessageAsync(video.Id!);
                    }
                    foreach (var path in ownedVideoPaths) await storage.DeleteVideoAsync(path);
                    await new RoomService(b).LeaveRoomAsync(roomId); await new RoomService(a).LeaveRoomAsync(roomId);
                    Check((await new RoomService(a).MyRoomsAsync()).Count == 0 && (await new RoomService(b).MyRoomsAsync()).Count == 0, "owned rows and objects removed and both room lists empty");
                }
                catch (Exception error) { errors.Add("owned cleanup (repair manifest retained): " + SafeLiveError(error)); }
            }
            File.WriteAllText(Path.Combine(OutputDirectory!, "result.json"), JsonSerializer.Serialize(new { Success = errors.Count == 0, Checks, Errors = errors, Limitations = limitations, ShellToastClickTested = false }));
            lifetimeWindow.CloseForQuit();
        }
    }
}
#endif
