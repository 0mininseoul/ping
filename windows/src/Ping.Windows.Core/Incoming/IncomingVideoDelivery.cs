using System.Collections.Concurrent;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Incoming;

public enum IncomingNotificationResult { Shown, Duplicate, Unavailable }
public sealed class IncomingDeliveryException() : Exception("Incoming notification is unavailable; delivery will be retried.");

public sealed class IncomingVideoDelivery(DateTimeOffset appStartedAt, Func<bool> autoPlayEnabled,
    Func<VideoMessage, CancellationToken, Task<IncomingNotificationResult>> notify,
    Func<VideoMessage, IncomingArrivalSource, CancellationToken, Task> enqueuePlayback,
    Func<string, CancellationToken, Task> acknowledge, Action<Exception>? onError = null, Func<DateTimeOffset>? now = null)
{
    private readonly IncomingDeliveryLedger ledger = new();
    private readonly ConcurrentDictionary<(string Uid, string Id), DateTimeOffset> pendingAcknowledgements = new();
    private readonly ConcurrentDictionary<(string Uid, string Id), Arrival> arrivals = new();
    private readonly Func<DateTimeOffset> clock = now ?? (() => DateTimeOffset.UtcNow);

    public async Task DeliverAsync(string uid, VideoMessage message, IncomingArrivalSource source, CancellationToken token = default)
    {
        var decision = IncomingArrivalPolicy.Decide(message, uid, source, appStartedAt, clock(), autoPlayEnabled());
        if (!decision.IsEligible || !decision.ShouldNotify) return;
        using var reservation = ledger.TryReserve(uid, IncomingItemKind.Video, message.Id!);
        if (reservation is null) return;
        var key = (uid, message.Id!);
        var arrival = arrivals.GetOrAdd(key, _ => new(source, message.ExpiresAt));
        decision = IncomingArrivalPolicy.Decide(message, uid, arrival.Source, appStartedAt, clock(), autoPlayEnabled());
        var result = await notify(message, token).ConfigureAwait(false);
        if (result == IncomingNotificationResult.Unavailable) throw new IncomingDeliveryException();
        if (decision.ShouldAutoPlay && result == IncomingNotificationResult.Shown)
            await enqueuePlayback(message, arrival.Source, token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        reservation.Commit();
        arrivals.TryRemove(key, out _);
        // Server acknowledgement is retried independently of already delivered local side effects.
        pendingAcknowledgements[(uid, message.Id!)] = message.ExpiresAt;
        await AcknowledgeAsync((uid, message.Id!), token).ConfigureAwait(false);
    }

    public async Task RetryAcknowledgementsAsync(string uid, CancellationToken token = default)
    {
        foreach (var (key, arrival) in arrivals)
            if (arrival.ExpiresAt <= clock()) arrivals.TryRemove(key, out _);
        foreach (var (key, expiresAt) in pendingAcknowledgements)
        {
            token.ThrowIfCancellationRequested();
            if (expiresAt <= clock()) { pendingAcknowledgements.TryRemove(key, out _); continue; }
            if (key.Uid == uid) await AcknowledgeAsync(key, token).ConfigureAwait(false);
        }
    }

    private sealed record Arrival(IncomingArrivalSource Source, DateTimeOffset ExpiresAt);

    private async Task AcknowledgeAsync((string Uid, string Id) key, CancellationToken token)
    {
        try
        {
            await acknowledge(key.Id, token).ConfigureAwait(false);
            pendingAcknowledgements.TryRemove(key, out _);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) { onError?.Invoke(error); }
    }
}
