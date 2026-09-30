using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.Core.Models;



namespace Ping.Windows.App.Playback;

public sealed class PlaybackViewModel : INotifyPropertyChanged
{
    public static readonly TimeSpan PausedTimeout = TimeSpan.FromSeconds(10);
    private const double FaceOnlyAspectRatio = 1;
    private const double ScreenFaceFallbackAspectRatio = 16.0 / 9.0;
    private const double MinimumScreenFacePlaybackAspectRatio = 0.5;
    private const double MaximumScreenFacePlaybackAspectRatio = 3.0;

    private readonly Func<CancellationToken, Task> markSeenAsync;
    private bool didMarkSeen;
    private bool isAwaitingDismissal;
    private bool isCloseRequested;
    private readonly SemaphoreSlim markingSeen = new(1, 1);

    public PlaybackViewModel(
        VideoMessage message,
        string localVideoPath,
        Func<CancellationToken, Task> markSeenAsync)
    {
        Message = message;
        LocalVideoPath = localVideoPath;
        this.markSeenAsync = markSeenAsync;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public event EventHandler? CloseRequested;

    public event EventHandler? PlaybackEnded;

    public event EventHandler? ReplayRequested;

    public VideoMessage Message { get; }

    public string LocalVideoPath { get; }

    public bool IsScreenFace => Message.CaptureMode == CaptureMode.ScreenFace;

    public double AspectRatio
    {
        get
        {
            var fallback = IsScreenFace ? ScreenFaceFallbackAspectRatio : FaceOnlyAspectRatio;
            var ratio = Message.AspectRatio ?? fallback;
            if (!double.IsFinite(ratio) || ratio <= 0)
            {
                return fallback;
            }

            return IsScreenFace
                ? Math.Clamp(
                    ratio,
                    MinimumScreenFacePlaybackAspectRatio,
                    MaximumScreenFacePlaybackAspectRatio)
                : ratio;
        }
    }

    public string SenderLabel => Message.SenderNickname;

    public bool IsAwaitingDismissal
    {
        get => isAwaitingDismissal;
        private set
        {
            if (isAwaitingDismissal == value)
            {
                return;
            }

            isAwaitingDismissal = value;
            OnPropertyChanged();
        }
    }

    public bool IsCloseRequested
    {
        get => isCloseRequested;
        private set
        {
            if (isCloseRequested == value)
            {
                return;
            }

            isCloseRequested = value;
            OnPropertyChanged();
        }
    }

    public async Task HandlePlaybackEndedAsync(CancellationToken cancellationToken = default)
    {
        if (IsCloseRequested) return;
        if (!IsAwaitingDismissal)
        {
            IsAwaitingDismissal = true;
            PlaybackEnded?.Invoke(this, EventArgs.Empty);
        }
        await markingSeen.WaitAsync(cancellationToken);
        try
        {
            if (!didMarkSeen && Message.Id is not null)
            {
                await markSeenAsync(cancellationToken);
                didMarkSeen = true;
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
        }
        finally { markingSeen.Release(); }
    }

    public void HandleEnter()
    {
        if (!IsAwaitingDismissal)
        {
            return;
        }

        IsAwaitingDismissal = false;
        ReplayRequested?.Invoke(this, EventArgs.Empty);
    }

    public void HandlePausedTimeoutElapsed() => RequestClose();

    public void HandleEscape() => RequestClose();

    private void RequestClose()
    {
        IsCloseRequested = true;
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
