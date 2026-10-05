#if PING_UI_SMOKE
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Ping.Windows.App.History;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using global::Windows.ApplicationModel.DataTransfer;
using global::Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    internal sealed record OwnedLiveOptions(string Config, string Sessions, string Fixtures);
    public static OwnedLiveOptions? OwnedLive { get; set; }
    private static string NormalizeLines(string text) => text.Replace("\r\n", "\n").Replace('\r', '\n');
    private static string SafeLiveError(Exception error) => error is SupabaseRequestException request
        ? $"HTTP {(int?)request.StatusCode} / code {request.ErrorCode}" : error.GetType().Name;

    private static async Task VerifyOwnedLiveAsync()
    {
        var options = OwnedLive!;
        var errors = new List<string>();
        var cleanup = new List<(string Label, Func<Task> Action)>();
        var windows = new List<(MainWindow Window, HistoryWindow Shell)>();
        var marker = "QA" + Guid.NewGuid().ToString("N")[..10];
        string? createdRoomId = null;
        var phase = "guard";
        // Keep a native window alive before the first asynchronous network operation.
        var lifetimeWindow = new MainWindow(); lifetimeWindow.InitializeTrayWindowBehavior(); lifetimeWindow.ShowShell();
        try
        {
            using var config = JsonDocument.Parse(File.ReadAllText(options.Config));
            Check(new Uri(config.RootElement.GetProperty("url").GetString()!).Host == "qxjtprxvjmaxlbtljcjw.supabase.co", "pinned Ping project guard");
            string Session(string name) => Path.Combine(options.Sessions, name, "SupabaseSession.json");
            var storedA = await new SupabaseSessionStore(Session("a")).LoadAsync();
            var storedB = await new SupabaseSessionStore(Session("b")).LoadAsync();
            Check(storedA is not null && storedB is not null && storedA.UserId != storedB.UserId, "existing distinct owned sessions required before any network request");
            using var httpA = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            using var httpB = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            using var a = new SupabaseClient(httpA, options.Config, Session("a"));
            using var b = new SupabaseClient(httpB, options.Config, Session("b"));
            var roomsA = new RoomService(a); var roomsB = new RoomService(b);
            var chatsA = new ChatMessageService(a); var chatsB = new ChatMessageService(b);
            var storageA = new StorageService(a); var storageB = new StorageService(b);
            var videosA = new MessageService(a, storageA); var videosB = new MessageService(b, storageB);
            phase = "restore";
            var uidA = await a.BootstrapAsync(); var uidB = await b.BootstrapAsync();
            Check(uidA == storedA!.UserId && uidB == storedB!.UserId, "restored owned identities without creating accounts");
            Check((await roomsA.MyRoomsAsync()).Count == 0 && (await roomsB.MyRoomsAsync()).Count == 0, "owned sessions have no existing rooms to disturb");
            try
            {
                phase = "room";
                var room = await roomsA.CreateRoomAsync(marker, "QA 민"); var roomId = room.Id!;
                createdRoomId = roomId;
                cleanup.Add(("leave owner", () => roomsA.LeaveRoomAsync(roomId)));
                cleanup.Add(("leave receiver", () => roomsB.LeaveRoomAsync(roomId)));
                File.WriteAllText(Path.Combine(OutputDirectory!, "owned-room.json"), JsonSerializer.Serialize(new { roomId }));
                var invite = await new InvitationService(a).SendAsync(uidB, roomId, "QA 민", marker);
                await new InvitationService(b).AcceptAsync(invite, "QA 서연");
                room = (await roomsA.MyRoomsAsync()).Single(r => r.Id == roomId);
                Check(room.MemberUids.Count == 2 && room.MemberUids.Contains(uidA) && room.MemberUids.Contains(uidB), "accepted room contains exactly the two owned identities");
                var vmA = new HistoryViewModel(roomsA, videosA, chatsA, new(a), new ChatMediaStorageService(storageA), () => uidA, new FixtureLinks(), _ => true);
                var vmB = new HistoryViewModel(roomsB, videosB, chatsB, new(b), new ChatMediaStorageService(storageB), () => uidB, new FixtureLinks(), _ => true);
                HistoryWindow Create(HistoryViewModel vm, MessageService videos, StorageService storage)
                {
                    var window = new MainWindow(); window.InitializeTrayWindowBehavior(); TestDisplayPlacement.Verify(window, Check);
                    var shell = new HistoryWindow(window, vm, (video, token) => storage.DownloadVideoAsync(video.VideoUrl, token), (_, _) => Task.CompletedTask,
                        videos, initialRoomId: roomId, loadOnStart: false, refreshInterval: TimeSpan.FromMinutes(5));
                    windows.Add((window, shell)); window.AttachMessenger(shell); window.ShowShell(); return shell;
                }
                var shellA = Create(vmA, videosA, storageA); var shellB = Create(vmB, videosB, storageB);
                await shellA.ReloadRoomsAsync(); await shellB.ReloadRoomsAsync();
                Check(vmA.SelectedRoom?.Id == roomId && vmB.SelectedRoom?.Id == roomId, "both native messengers load the accepted live room");
                async Task Send(HistoryWindow shell, HistoryViewModel vm, string body)
                {
                    vm.DraftText = body;
                    await Task.Delay(60);
                    var button = (Button)shell.FindName("SendButton");
                    Check(button.IsEnabled && NormalizeLines(((TextBox)shell.FindName("ChatBox")).Text) == NormalizeLines(body), "native composer binding enables explicit send");
                    ((IInvokeProvider)new ButtonAutomationPeer(button).GetPattern(PatternInterface.Invoke)).Invoke();
                    await UntilAsync(() => !vm.IsSending && vm.DraftText == "", 25);
                }
                phase = "chat";
                const string body = "한글 채팅 🙂\nhttps://example.com/help 와 qa@example.net";
                await Send(shellA, vmA, body); await shellB.RefreshNowAsync();
                var chat = vmB.Chats.Single(c => NormalizeLines(c.Message.Body) == body);
                Check(!chat.IsMine && vmA.Chats.Single(c => c.Message.Id == chat.Message.Id).IsMine, "native sent and received alignment follows actual server identities");
                Check(vmB.Timeline.All(row => row.SenderVisibility == Visibility.Collapsed), "live one-to-one room hides sender labels");
                await Task.Delay(100);
                Check(Descendants(shellB).OfType<TextBlock>().Any(t => t.Name == "LinkedChatBody" && t.Inlines.OfType<Microsoft.UI.Xaml.Documents.Hyperlink>().Count() == 2), "received native body keeps individual web and email links");
                phase = "reply";
                vmB.BeginReplyToChat(chat); await Send(shellB, vmB, "답장도 도착해요 😊"); await shellA.RefreshNowAsync();
                Check(vmA.Chats.Any(c => c.Message.ReplyToChatId == chat.Message.Id && c.ReplyPreview?.Contains("한글 채팅") == true), "live reply arrives with quoted preview in native timeline");
                await vmB.ToggleReactionAsync(ReactionTargetKind.Chat, chat.Message.Id, "👍"); await shellA.RefreshNowAsync();
                Check(vmA.Reactions.Any(r => r.TargetId == chat.Message.Id && r.TotalCount == 1), "live reaction reaches native sender timeline");
                phase = "photo";
                var file = await StorageFile.GetFileFromPathAsync(Path.Combine(options.Fixtures, "owned-photo.png"));
                var data = new DataPackage(); data.SetStorageItems([file]); await shellA.ImportImageAsync(data.GetView());
                await Send(shellA, vmA, "사진 문구");
                var ownedPhotoPath = vmA.Chats.Single(c => c.Message.Body == "사진 문구").Message.MediaPath!;
                Check(ownedPhotoPath.StartsWith(uidA + "/chat-images/", StringComparison.Ordinal), "photo remains inside the owned sender storage prefix");
                cleanup.Add(("delete known photo object", () => storageA.DeleteChatMediaAsync(ownedPhotoPath)));
                File.WriteAllText(Path.Combine(OutputDirectory!, "owned-media.json"), JsonSerializer.Serialize(new { roomId, photoPath = ownedPhotoPath }));
                await shellB.RefreshNowAsync();
                var photo = vmB.Chats.Single(c => c.Message.Body == "사진 문구");
                Check(photo.Message.MediaWidth == 960 && photo.Message.MediaHeight == 640, "native photo input uploads live metadata");
                var downloaded = await storageB.DownloadChatMediaAsync(photo.Message.MediaPath!, "png");
                Check(SHA256.HashData(File.ReadAllBytes(file.Path)).SequenceEqual(SHA256.HashData(File.ReadAllBytes(downloaded))), "native photo path preserves source bytes across private storage");
                await UntilAsync(() => Descendants(shellB).OfType<Image>().Any(i => i.DataContext is TimelineHistoryItem { Chat.Message.MediaPath: not null } && i.Source is Microsoft.UI.Xaml.Media.Imaging.BitmapImage { PixelWidth: 960 }), 10);
                Check(true, "received photo decodes inside native timeline");
                phase = "video";
                var videoId = Guid.NewGuid().ToString();
                File.WriteAllText(Path.Combine(OutputDirectory!, "owned-video.json"), JsonSerializer.Serialize(new { roomId, videoPath = $"{uidA}/{videoId}.mp4" }));
                cleanup.Add(("delete video object", () => storageA.DeleteVideoAsync($"{uidA}/{videoId}.mp4")));
                await videosA.SendAsync(new([room], Path.Combine(options.Fixtures, "owned-face-source.mp4"), new(0.25, 0.75), uidA, "QA 민", CaptureMode.FaceOnly, 1, false, videoId));
                await shellB.RefreshNowAsync(); await Task.Delay(100);
                var videoButton = Descendants(shellB).OfType<Button>().Single(button => button.DataContext is TimelineHistoryItem { Video.Message.VideoId: var id } && id == videoId && button.Content is Grid);
                ((IInvokeProvider)new ButtonAutomationPeer(videoButton).GetPattern(PatternInterface.Invoke)).Invoke();
                await UntilAsync(() => Descendants(shellB).OfType<TextBlock>().Any(t => t.Name == "InlineFaceStatus" && t.Text == "다시 재생"), 15);
                var video = vmB.Videos.Single(v => v.VideoId == videoId);
                Check((await videosA.GetAsync(video.Message.Id!))?.Status == MessageStatus.Seen, "native inline completion marks actual server video seen");
                Check(Descendants(shellB).OfType<MediaPlayerElement>().Single(p => p.Name == "InlineFaceElement").MediaPlayer.PlaybackSession.NaturalVideoWidth > 0, "native inline player decodes the actual private download");
                shellB.RequestedTheme = ElementTheme.Light; await Task.Delay(100); await RenderAsync(shellB, "live-messenger-light.png");
                shellB.RequestedTheme = ElementTheme.Dark; await Task.Delay(100); await RenderAsync(shellB, "live-messenger-dark.png");
            }
            finally
            {
                foreach (var owned in windows)
                {
                    try { await owned.Shell.DetachAsync(); } catch (Exception error) { errors.Add("detach: " + SafeLiveError(error)); }
                    owned.Window.CloseForQuit();
                }
                windows.Clear();
                var enumerationComplete = true;
                // Only rows in the uniquely created room are eligible for cleanup.
                if (createdRoomId is { } roomId)
                {
                    foreach (var client in new[] { a, b })
                    {
                        try
                        {
                            var chats = new ChatMessageService(client);
                            foreach (var chat in await chats.RoomChatMessagesAsync(roomId))
                                if (chat.SenderUid == client.CurrentUid)
                                {
                                    if (chat.MediaPath is { } path && path.StartsWith(client.CurrentUid + "/chat-images/", StringComparison.Ordinal) && !File.Exists(Path.Combine(OutputDirectory!, "owned-media.json")))
                                        cleanup.Add(("delete photo object", () => new StorageService(client).DeleteChatMediaAsync(path)));
                                    var id = chat.Id; cleanup.Add(("delete owned chat", () => chats.DeleteChatAsync(id!)));
                                }
                        }
                        catch (Exception error) { enumerationComplete = false; errors.Add("enumerate owned chats: " + SafeLiveError(error)); }
                    }
                    try
                    {
                        foreach (var video in await videosA.RoomMessagesAsync(roomId))
                        { var id = video.Id!; cleanup.Add(("delete video row", () => videosA.DeleteMessageAsync(id))); }
                    }
                    catch (Exception error) { enumerationComplete = false; errors.Add("enumerate owned videos: " + SafeLiveError(error)); }
                }
                foreach (var item in cleanup.AsEnumerable().Reverse())
                {
                    if (!enumerationComplete && item.Label.StartsWith("leave ", StringComparison.Ordinal)) continue;
                    try { await item.Action(); Step("CLEAN " + item.Label); }
                    catch (Exception error) { errors.Add(item.Label + ": " + SafeLiveError(error)); }
                }
                Check((await roomsA.MyRoomsAsync()).Count == 0 && (await roomsB.MyRoomsAsync()).Count == 0, "both owned live room lists are empty after cleanup");
            }
        }
        catch (Exception error) { errors.Add(phase + ": " + SafeLiveError(error)); }
        finally
        {
            foreach (var owned in windows) { try { await owned.Shell.DetachAsync(); } catch { } owned.Window.CloseForQuit(); }
            File.WriteAllText(Path.Combine(OutputDirectory!, "result.json"), JsonSerializer.Serialize(new { Success = errors.Count == 0, Checks, Errors = errors, FixtureOnly = false, OwnedSessionsOnly = true }, new JsonSerializerOptions { WriteIndented = true }));
            lifetimeWindow.CloseForQuit();
        }
    }
}
#endif
