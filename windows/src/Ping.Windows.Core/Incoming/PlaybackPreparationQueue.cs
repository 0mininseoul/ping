using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Incoming;

public sealed class PlaybackPreparationQueue : IAsyncDisposable
{
    private readonly Func<VideoMessage, CancellationToken, Task<string>> prepare;
    private readonly Func<string, VideoMessage, string, IncomingArrivalSource, CancellationToken, Task> present;
    private readonly Action<Exception>? onError;
    private readonly TimeSpan retryDelay;
    private readonly SemaphoreSlim preparing;
    private readonly CancellationTokenSource lifetime = new();
    private readonly object sync = new();
    private readonly Dictionary<(string Uid, string Id), Pending> pending = new();
    private Task? stopping;
    private bool disposed;

    public PlaybackPreparationQueue(Func<VideoMessage, CancellationToken, Task<string>> prepare,
        Func<string, VideoMessage, string, IncomingArrivalSource, CancellationToken, Task> present,
        Action<Exception>? onError = null, int maximumConcurrency = 2, TimeSpan? retryDelay = null)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumConcurrency);
        this.prepare = prepare;
        this.present = present;
        this.onError = onError;
        this.retryDelay = retryDelay ?? TimeSpan.FromSeconds(1);
        preparing = new(maximumConcurrency, maximumConcurrency);
    }

    public Task RequestAsync(string uid, VideoMessage message, IncomingArrivalSource source, CancellationToken token = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uid);
        ArgumentException.ThrowIfNullOrWhiteSpace(message.Id);
        token.ThrowIfCancellationRequested();
        lock (sync)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            var key = (uid, message.Id!);
            if (pending.TryGetValue(key, out var existing))
            {
                if (source is IncomingArrivalSource.NotificationClick or IncomingArrivalSource.HistoryReplay) existing.Source = source;
                return existing.Completion.Task.WaitAsync(token);
            }
            var request = new Pending(message, source);
            pending[key] = request;
            request.Work = Task.Run(() => RunAsync(key, request, lifetime.Token));
            return request.Completion.Task.WaitAsync(token);
        }
    }

    public void Enqueue(string uid, VideoMessage message, IncomingArrivalSource source)
    {
        _ = ObserveAsync(RequestAsync(uid, message, source));
    }

    private static async Task ObserveAsync(Task task)
    {
        try { await task.ConfigureAwait(false); }
        catch (Exception) { } // The owned worker reports failures; automatic delivery has no awaiting UI caller.
    }

    private async Task RunAsync((string Uid, string Id) key, Pending request, CancellationToken token)
    {
        try
        {
            string path;
            for (var attempt = 0; ; attempt++)
            {
                await preparing.WaitAsync(token).ConfigureAwait(false);
                try { path = await prepare(request.Message, token).ConfigureAwait(false); break; }
                catch (IOException) when (attempt < 2) { }
                catch (HttpRequestException) when (attempt < 2) { }
                finally { preparing.Release(); }
                await Task.Delay(retryDelay * (attempt + 1), token).ConfigureAwait(false);
            }
            token.ThrowIfCancellationRequested();
            IncomingArrivalSource source;
            lock (sync) source = request.Source;
            await present(key.Uid, request.Message, path, source, token).ConfigureAwait(false);
            request.Completion.TrySetResult();
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { request.Completion.TrySetCanceled(token); }
        catch (Exception error)
        {
            request.Completion.TrySetException(error);
            onError?.Invoke(error);
        }
        finally { lock (sync) pending.Remove(key); }
    }

    public ValueTask DisposeAsync()
    {
        lock (sync)
        {
            if (stopping is not null) return new(stopping);
            disposed = true;
            lifetime.Cancel();
            stopping = FinishAsync(pending.Values.Select(request => request.Work!).ToArray());
            return new(stopping);
        }
    }

    private async Task FinishAsync(Task[] work)
    {
        await Task.WhenAll(work).ConfigureAwait(false);
        lifetime.Dispose();
        preparing.Dispose();
    }

    private sealed class Pending(VideoMessage message, IncomingArrivalSource source)
    {
        public VideoMessage Message { get; } = message;
        public IncomingArrivalSource Source { get; set; } = source;
        public TaskCompletionSource Completion { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task? Work { get; set; }
    }
}
