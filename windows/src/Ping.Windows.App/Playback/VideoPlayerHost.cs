#if WINDOWS
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Dispatching;
using Windows.Media.Core;
using Windows.Media.Playback;

namespace Ping.Windows.App.Playback;

public sealed class VideoPlayerHost : IDisposable
{
    private MediaPlayer? player;
    private DispatcherQueue? dispatcherQueue;
    private Func<CancellationToken, Task>? endedAsync;
    private bool disposed;
    private readonly CancellationTokenSource lifetime = new();
    public event EventHandler? PlaybackFailed;

    public void Attach(
        MediaPlayerElement element,
        string localVideoPath,
        Func<CancellationToken, Task> endedAsync)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        this.endedAsync = endedAsync;
        dispatcherQueue = element.DispatcherQueue;
        player?.Dispose();
        player = new MediaPlayer
        {
            AutoPlay = false,
            Source = MediaSource.CreateFromUri(new Uri(localVideoPath, UriKind.Absolute))
        };
        player.MediaEnded += HandleMediaEnded;
        player.MediaFailed += HandleMediaFailed;
        element.SetMediaPlayer(player);
    }

    public Task PlayAsync()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        player?.Play();
        return Task.CompletedTask;
    }

    public void Replay()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (player is null)
        {
            return;
        }

        player.Position = TimeSpan.Zero;
        player.Play();
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        if (player is not null)
        {
            player.MediaEnded -= HandleMediaEnded;
            player.MediaFailed -= HandleMediaFailed;
            player.Dispose();
            player = null;
        }

        disposed = true;
        lifetime.Cancel();
        lifetime.Dispose();
    }

    private void HandleMediaEnded(MediaPlayer sender, object args)
    {
        if (endedAsync is null || disposed)
        {
            return;
        }

        if (dispatcherQueue is { } queue && !queue.HasThreadAccess)
        {
            _ = queue.TryEnqueue(() => RunEndedHandler());
            return;
        }

        RunEndedHandler();
    }

    private void HandleMediaFailed(MediaPlayer sender, MediaPlayerFailedEventArgs args)
    {
        if (dispatcherQueue is { } queue) _ = queue.TryEnqueue(() => { if (!disposed) PlaybackFailed?.Invoke(this, EventArgs.Empty); });
    }

    private void RunEndedHandler()
    {
        if (endedAsync is null || disposed)
        {
            return;
        }

        _ = endedAsync(lifetime.Token).ContinueWith(
            task =>
            {
                _ = task.Exception;
            },
            CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted,
            TaskScheduler.Default);
    }
}
#endif
