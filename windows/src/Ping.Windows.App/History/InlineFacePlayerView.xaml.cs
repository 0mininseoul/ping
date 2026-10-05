using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Ping.Windows.App.Playback;
using Ping.Windows.App.UI;

namespace Ping.Windows.App.History;

public sealed partial class InlineFacePlayerView : UserControl, IDisposable
{
    private VideoPlayerHost? host;
    private bool disposed;
    private bool loading;
    public event EventHandler? CollapseRequested;
    public event EventHandler? ReplayRequested;
    public bool HasPlayer => host is not null;

    public InlineFacePlayerView() => InitializeComponent();
    private void SurfaceLoaded(object sender, RoutedEventArgs args) => RoundedCompositionClip.Apply(InlineFaceSurface, 128, 128, 64);
    private void Collapse_Click(object sender, RoutedEventArgs args) => CollapseRequested?.Invoke(this, EventArgs.Empty);
    private void Replay_Click(object sender, RoutedEventArgs args) => ReplayRequested?.Invoke(this, EventArgs.Empty);
    public bool TryBeginLoading()
    {
        if (disposed || loading) return false;
        loading = true;
        LoadingRing.IsActive = true; LoadingRing.Visibility = Visibility.Visible;
        InlineFaceStatus.Text = "불러오는 중…"; InlineFaceReplayButton.IsEnabled = false;
        return true;
    }
    public async Task StartAsync(string path, Func<CancellationToken, Task> markSeenAsync)
    {
        if (disposed) return;
        loading = false;
        host?.Dispose();
        host = new VideoPlayerHost();
        host.PlaybackFailed += (_, _) => ShowFailure();
        host.Attach(InlineFaceElement, path, async token =>
        {
            if (disposed) return;
            InlineFaceStatus.Text = "다시 재생";
            await markSeenAsync(token);
        });
        LoadingRing.IsActive = false; LoadingRing.Visibility = Visibility.Collapsed;
        InlineFaceStatus.Text = "재생 중 · 다시 재생"; InlineFaceReplayButton.IsEnabled = true;
        await host.PlayAsync();
    }
    public void Replay()
    {
        if (!disposed && host is not null) { InlineFaceStatus.Text = "재생 중 · 다시 재생"; host.Replay(); }
    }
    public void ShowFailure()
    {
        if (disposed) return;
        loading = false;
        host?.Dispose(); host = null; InlineFaceElement.SetMediaPlayer(null);
        LoadingRing.IsActive = false; LoadingRing.Visibility = Visibility.Collapsed;
        InlineFaceStatus.Text = "불러올 수 없어요. 다시 시도"; InlineFaceReplayButton.IsEnabled = true;
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; loading = false; host?.Dispose(); host = null;
        InlineFaceElement.SetMediaPlayer(null); LoadingRing.IsActive = false;
    }
}
