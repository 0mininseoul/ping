using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Capture;

public sealed record AutoReplyIdentity(string Uid, string Nickname, bool AllowsLocalSave);

public sealed class AutoFaceReplyCoordinator : IAsyncDisposable
{
    private readonly object sync = new();
    private readonly CameraOwnership camera;
    private readonly CaptureActivityState activity;
    private readonly DateTimeOffset appStartedAt;
    private readonly Func<AutoReplyIdentity?> identity;
    private readonly Func<bool> authorized;
    private readonly Func<CameraLease, TimeSpan, CancellationToken, Task<string>> record;
    private readonly Func<VideoMessage, CancellationToken, Task<IAsyncDisposable>> indicator;
    private readonly Func<AutoReplyVideoInput, Func<bool>, CancellationToken, Task<bool>> send;
    private readonly Action<string> deleteTemporaryClip;
    private readonly Func<DateTimeOffset> clock;
    private readonly Action<Exception> onError;
    private readonly CancellationTokenSource lifetime = new();
    private readonly Dictionary<(string Uid, string Id), DateTimeOffset> observed = new();
    private Task inFlight = Task.CompletedTask;
    private Task? stopTask;
    private bool stopped;
    private int disposed;

    public AutoFaceReplyCoordinator(CameraOwnership camera, CaptureActivityState activity, DateTimeOffset appStartedAt,
        Func<AutoReplyIdentity?> identity, Func<bool> authorized, Func<CameraLease, TimeSpan, CancellationToken, Task<string>> record,
        Func<VideoMessage, CancellationToken, Task<IAsyncDisposable>> indicator,
        Func<AutoReplyVideoInput, Func<bool>, CancellationToken, Task<bool>> send, Action<string> deleteTemporaryClip,
        Func<DateTimeOffset>? clock = null, Action<Exception>? onError = null)
    {
        this.camera = camera;
        this.activity = activity;
        this.appStartedAt = appStartedAt;
        this.identity = identity;
        this.authorized = authorized;
        this.record = record;
        this.indicator = indicator;
        this.send = send;
        this.deleteTemporaryClip = deleteTemporaryClip;
        this.clock = clock ?? (() => DateTimeOffset.UtcNow);
        this.onError = onError ?? (_ => { });
        activity.Interrupted += camera.InterruptAutomatic;
    }

    public AutoFaceReplyDecision HandleIncoming(VideoMessage message, IncomingArrivalSource source)
    {
        CameraLease lease;
        AutoReplyIdentity current;
        TaskCompletionSource completion;
        long generation;
        lock (sync)
        {
            if (stopped || identity() is not { } account) return AutoFaceReplyDecision.InvalidMessage;
            current = account;
            var now = clock();
            foreach (var expired in observed.Where(pair => pair.Value < now).Select(pair => pair.Key).ToArray()) observed.Remove(expired);
            var key = (current.Uid, message.Id ?? "");
            var decision = AutoFaceReplyPolicy.Decide(message, current.Uid, source, appStartedAt, now,
                observed.ContainsKey(key), activity.IsBlocked, authorized(), camera.IsBusy || !inFlight.IsCompleted);

            // Catch-up and skipped camera work must never become a delayed Live recording on a later poll.
            if (source is IncomingArrivalSource.Live or IncomingArrivalSource.StartupCatchUp or IncomingArrivalSource.ReconnectCatchUp
                && !string.IsNullOrWhiteSpace(message.Id) && message.ReceiverUid == current.Uid && message.CreatedAt is { } created)
                observed.TryAdd(key, created + AutoFaceReplyPolicy.FreshnessWindow);
            if (decision != AutoFaceReplyDecision.Record) return decision;
            if (camera.TryAcquire(CameraPurpose.AutomaticReply) is not { } acquired) return AutoFaceReplyDecision.CameraBusy;
            lease = acquired;
            generation = activity.Generation;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            inFlight = completion.Task;
        }
        _ = RunAttemptAsync(message, current, lease, generation, completion);
        return AutoFaceReplyDecision.Record;
    }

    private async Task RunAttemptAsync(VideoMessage message, AutoReplyIdentity account, CameraLease lease,
        long generation, TaskCompletionSource completion)
    {
        IAsyncDisposable? visibleIndicator = null;
        string? clip = null;
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token, lease.Token);
        var token = cancellation.Token;
        bool CanContinue() => !token.IsCancellationRequested && identity()?.Uid == account.Uid && authorized()
            && !activity.IsBlocked && AutoFaceReplyPolicy.Recheck(message, clock(), activity.WasInterruptedSince(generation)) == AutoFaceReplyDecision.Record;
        try
        {
            if (!CanContinue()) return;
            visibleIndicator = await indicator(message, token).ConfigureAwait(false);
            if (!CanContinue()) return;
            clip = await record(lease, AutoFaceReplyPolicy.ClipDuration, token).ConfigureAwait(false);
            if (!CanContinue()) return;
            await send(new(message, clip, account.Uid, account.Nickname, account.AllowsLocalSave), CanContinue, token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception error) { ReportError(error); }
        finally
        {
            if (clip is not null)
            {
                try { deleteTemporaryClip(clip); }
                catch (Exception error) { ReportError(error); }
            }
            if (visibleIndicator is not null)
            {
                try { await visibleIndicator.DisposeAsync().ConfigureAwait(false); }
                catch (Exception error) { ReportError(error); }
            }
            lease.Dispose();
            completion.TrySetResult();
        }
    }

    private void ReportError(Exception error)
    {
        try { onError(error); }
        catch { }
    }

    public Task WaitForIdleAsync() { lock (sync) return inFlight; }

    public Task StopAsync()
    {
        Task pending;
        TaskCompletionSource completion;
        lock (sync)
        {
            if (stopTask is not null) return stopTask;
            stopped = true;
            pending = inFlight;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            stopTask = completion.Task;
        }
        _ = StopCoreAsync(pending, completion);
        return completion.Task;
    }

    private async Task StopCoreAsync(Task pending, TaskCompletionSource completion)
    {
        try
        {
            try { lifetime.Cancel(); }
            catch (AggregateException error) { ReportError(error); }
            await pending.ConfigureAwait(false);
        }
        finally { completion.TrySetResult(); }
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        activity.Interrupted -= camera.InterruptAutomatic;
        await StopAsync().ConfigureAwait(false);
        lifetime.Dispose();
    }
}
