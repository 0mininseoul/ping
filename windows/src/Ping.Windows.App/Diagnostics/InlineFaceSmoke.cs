#if PING_UI_SMOKE
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Ping.Windows.App.History;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using global::Windows.Media.Editing;
using global::Windows.Media.MediaProperties;
using global::Windows.Media.Transcoding;
using global::Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    private static async Task VerifyInlineFaceAsync()
    {
        var file = await (await StorageFolder.GetFolderFromPathAsync(OutputDirectory!)).CreateFileAsync("inline-face-owned.mp4", CreationCollisionOption.FailIfExists);
        var composition = new MediaComposition();
        composition.Clips.Add(MediaClip.CreateFromColor(Colors.CornflowerBlue, TimeSpan.FromSeconds(3)));
        Check(await composition.RenderToFileAsync(file, MediaTrimmingPreference.Precise, MediaEncodingProfile.CreateMp4(VideoEncodingQuality.Wvga)) == TranscodeFailureReason.None,
            "inline fixture owns a real3-second MP4 without camera or network");
        var rpc = new FixtureRpc(); var storage = new FixtureStorage();
        var vm = new HistoryViewModel(new(rpc), new(rpc, storage), new(rpc), new(rpc), storage, () => "me", new FixtureLinks());
        var window = new MainWindow(); window.InitializeTrayWindowBehavior(); var external = 0; var downloads = 0;
        TaskCompletionSource<string>? pendingDownload = null; var shouldFail = false; CancellationToken lastToken = default;
        var shell = new HistoryWindow(window, vm, (_, token) =>
        {
            downloads++; lastToken = token;
            return pendingDownload?.Task ?? (shouldFail ? Task.FromException<string>(new IOException("owned load failure")) : Task.FromResult(file.Path));
        }, (_, _) => Task.CompletedTask, new(rpc, storage), loadOnStart: false,
            playVideoAsync: (_, _) => { external++; return Task.CompletedTask; });
        void Invoke(string name) => ((IInvokeProvider)new ButtonAutomationPeer(Descendants(shell).OfType<Button>().Single(b => b.Name == name)).GetPattern(PatternInterface.Invoke)).Invoke();
        Button VideoButton() => Descendants(shell).OfType<Button>().Single(b => b.DataContext is TimelineHistoryItem { Video: not null } && b.Content is Grid);
        void Open() => ((IInvokeProvider)new ButtonAutomationPeer(VideoButton()).GetPattern(PatternInterface.Invoke)).Invoke();
        MediaPlayerElement? Player() => Descendants(shell).OfType<MediaPlayerElement>().SingleOrDefault(p => p.Name == "InlineFaceElement");
        try
        {
            window.AttachMessenger(shell); window.ShowShell(); await shell.ReloadRoomsAsync(); await Task.Delay(150);
            Open(); await Task.Delay(150);
            Check(Player() is not null && external == 0, "face history click expands inside the conversation instead of a floating player");
            var element = Player()!;
            Check(Math.Abs(element.ActualWidth - 128) < 1 && Math.Abs(element.ActualHeight - 128) < 1,
                "inline face renders in the Mac128-DIP circle");
            var surface = (FrameworkElement)element.Parent;
            Check(ElementCompositionPreview.GetElementVisual(surface).Clip is not null, "inline video and loading surface share a circular clip");
            var player = element.MediaPlayer;
            await shell.RefreshNowAsync(); await Task.Delay(120);
            Check(ReferenceEquals(Player(), element) && ReferenceEquals(Player()!.MediaPlayer, player) && downloads == 1,
                "timeline refresh retains the same player without downloading or restarting");
            await UntilAsync(() => Descendants(shell).OfType<TextBlock>().Any(t => t.Name == "InlineFaceStatus" && t.Text == "다시 재생"), 5);
            Check(rpc.SeenCalls == 1, "inline completion marks received video seen once");
            Check(player!.PlaybackSession.NaturalVideoWidth > 0 && player.PlaybackSession.NaturalVideoHeight > 0,
                "native inline player decodes the owned video stream");
            await RenderAsync(shell, "messenger-inline-face.png");
            Invoke("InlineFaceReplayButton"); await Task.Delay(150);
            Check(player!.Position < TimeSpan.FromSeconds(1), "inline replay restarts the existing cached player");
            Invoke("InlineFaceCollapseButton"); await Task.Delay(100);
            Check(Player() is null && element.MediaPlayer is null, "collapsing releases the old player and restores thumbnail");
            pendingDownload = new(); Open(); await Task.Delay(100); var loadingElement = Player()!;
            var downloadCount = downloads;
            var videoPanel = Descendants(shell).OfType<StackPanel>().Single(p => p.Visibility == Visibility.Visible && p.ContextFlyout is MenuFlyout && p.DataContext is TimelineHistoryItem { Video: not null });
            var replayMenu = (MenuFlyout)videoPanel.ContextFlyout;
            replayMenu.ShowAt(loadingElement); await Task.Delay(100);
            ((IInvokeProvider)new MenuFlyoutItemAutomationPeer(replayMenu.Items.OfType<MenuFlyoutItem>().Single(i => i.Text == "다시 재생")).GetPattern(PatternInterface.Invoke)).Invoke();
            await Task.Delay(100); replayMenu.Hide();
            Check(downloads == downloadCount, "context replay during a pending load cannot start another download or player");
            await shell.FocusRoomAsync("b"); pendingDownload.SetResult(file.Path); await Task.Delay(100);
            Check(lastToken.IsCancellationRequested && Player() is null && loadingElement.MediaPlayer is null,
                "room switch cancels pending load and rejects late playback completion");
            pendingDownload = null; rpc.VideoMode = CaptureMode.ScreenFace; await shell.FocusRoomAsync("a"); await Task.Delay(100); Open(); await Task.Delay(100);
            Check(external == 1 && Player() is null, "screen-face history preserves the large external playback route");
            rpc.VideoMode = CaptureMode.FaceOnly; await shell.RefreshNowAsync(); await Task.Delay(100); shouldFail = true; Open(); await Task.Delay(100);
            Check(Descendants(shell).OfType<TextBlock>().Any(t => t.Name == "InlineFaceStatus" && t.Text.Contains("불러올 수")),
                "failed inline load shows a readable retry state");
            shouldFail = false; Invoke("InlineFaceReplayButton"); await Task.Delay(100);
            Check(Player()?.MediaPlayer is not null, "inline retry recovers using the existing download service");
            rpc.SeenGate = new();
            await UntilAsync(() => rpc.SeenCalls == 2, 5);
            Invoke("InlineFaceReplayButton"); await Task.Delay(3300);
            Check(rpc.SeenCalls == 2, "replay while seen RPC is pending does not issue duplicate seen calls");
            await shell.FocusRoomAsync("b"); await shell.FocusRoomAsync("a"); await Task.Delay(100); Open();
            rpc.SeenGate.SetResult(); rpc.SeenGate = null;
            await Task.Delay(3300);
            Check(rpc.SeenCalls == 3, "late seen response from closed expansion cannot suppress the next expansion read marker");
            var detachedElement = Player()!; await shell.DetachAsync();
            Check(detachedElement.MediaPlayer is null && Player() is null, "account detach releases inline media and content");
        }
        finally { await shell.DetachAsync(); window.CloseForQuit(); }
    }
}
#endif
