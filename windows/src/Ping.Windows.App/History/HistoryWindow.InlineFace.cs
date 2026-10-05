using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.History;

public sealed partial class HistoryWindow
{
    private VideoMessage? inlineMessage;
    private InlineFacePlayerView? inlineFace;
    private ContentControl? inlineHost;
    private CancellationTokenSource? inlineLifetime;
    private bool inlineSeen;

    private async Task ToggleInlineFaceAsync(VideoMessage video)
    {
        if (detached || video.Id is null || video.RoomId != viewModel.SelectedRoom?.Id) return;
        if (inlineMessage?.Id == video.Id) { CloseInlineFace(); return; }
        CloseInlineFace();
        inlineMessage = video; inlineLifetime = new(); inlineSeen = false;
        var content = new InlineFacePlayerView(); inlineFace = content;
        content.CollapseRequested += (_, _) => CloseInlineFace();
        content.ReplayRequested += async (_, _) =>
        {
            if (!ReferenceEquals(inlineFace, content)) return;
            if (content.HasPlayer) content.Replay();
            else await LoadInlineFaceAsync(content, video, inlineLifetime!.Token);
        };
        SyncInlineFaceRows();
        await LoadInlineFaceAsync(content, video, inlineLifetime.Token);
    }
    private async Task LoadInlineFaceAsync(InlineFacePlayerView content, VideoMessage video, CancellationToken token)
    {
        if (!content.TryBeginLoading()) return;
        try
        {
            var path = await downloadVideoAsync(video, token);
            if (detached || token.IsCancellationRequested || !ReferenceEquals(inlineFace, content)) return;
            await content.StartAsync(path, async playbackToken =>
            {
                if (inlineSeen || token.IsCancellationRequested || playbackToken.IsCancellationRequested || !ReferenceEquals(inlineFace, content)) return;
                inlineSeen = true;
                try { await viewModel.MarkInlineVideoSeenAsync(video, token); }
                catch (OperationCanceledException) { if (!token.IsCancellationRequested && ReferenceEquals(inlineFace, content)) inlineSeen = false; }
                catch (Exception)
                {
                    if (!detached && !token.IsCancellationRequested && ReferenceEquals(inlineFace, content))
                    { inlineSeen = false; ReportConnectionStatus("읽음 상태를 갱신하지 못했어요.", true); }
                }
            });
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception) { if (!detached && !token.IsCancellationRequested && ReferenceEquals(inlineFace, content)) content.ShowFailure(); }
    }
    private void CloseInlineFace()
    {
        inlineLifetime?.Cancel(); inlineLifetime?.Dispose(); inlineLifetime = null;
        inlineMessage = null;
        if (inlineHost is not null) inlineHost.Content = null;
        inlineHost = null; inlineFace?.Dispose(); inlineFace = null;
        SyncInlineFaceRows();
    }
    private void SyncInlineFaceRows(bool closeIfMissing = false)
    {
        if (closeIfMissing && inlineMessage is { } active && !viewModel.Videos.Any(v => v.Message.Id == active.Id && v.Message.RoomId == active.RoomId))
        { CloseInlineFace(); return; }
        foreach (var row in viewModel.Videos) row.IsInlineExpanded = inlineMessage is not null && row.Message.Id == inlineMessage.Id && row.Message.RoomId == inlineMessage.RoomId;
        foreach (var host in InlineHosts(VideosList)) AttachInlineHost(host);
    }
    private void InlineHost_Loaded(object sender, RoutedEventArgs args) => AttachInlineHost((ContentControl)sender);
    private void InlineHost_DataContextChanged(FrameworkElement sender, DataContextChangedEventArgs args) => AttachInlineHost((ContentControl)sender);
    private void InlineHost_Unloaded(object sender, RoutedEventArgs args)
    {
        if (ReferenceEquals(sender, inlineHost)) { inlineHost.Content = null; inlineHost = null; }
    }
    private void AttachInlineHost(ContentControl host)
    {
        if (inlineFace is null || host.DataContext is not TimelineHistoryItem { Video.IsInlineExpanded: true } row || row.Video.Message.Id != inlineMessage?.Id) return;
        if (ReferenceEquals(inlineHost, host)) return;
        if (inlineHost is not null) inlineHost.Content = null;
        inlineHost = host; host.Content = inlineFace;
    }
    private static IEnumerable<ContentControl> InlineHosts(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is ContentControl { Name: "InlineFaceHost" } host) yield return host;
            else foreach (var nested in InlineHosts(child)) yield return nested;
        }
    }
}
