using System.Collections.Concurrent;
using System.Globalization;
using System.Threading.Channels;

namespace Ping.Windows.Core.Realtime;

public sealed class RealtimeConnection
{
    private readonly IRealtimeTransport transport;
    private readonly RealtimeConnectionOptions options;
    private readonly ConcurrentDictionary<string, PendingJoin> joins = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> joinReferences = new(StringComparer.Ordinal);
    private readonly Channel<RealtimeChange> changes = Channel.CreateBounded<RealtimeChange>(new BoundedChannelOptions(256)
    {
        SingleReader = true, SingleWriter = true, FullMode = BoundedChannelFullMode.DropOldest
    });
    private PendingHeartbeat? heartbeat;
    private int reference;
    private int started;

    public RealtimeConnection(IRealtimeTransport transport, RealtimeConnectionOptions? options = null)
    {
        this.transport = transport;
        this.options = options ?? RealtimeConnectionOptions.Default;
        if (this.options.JoinTimeout <= TimeSpan.Zero || this.options.HeartbeatInterval <= TimeSpan.Zero || this.options.HeartbeatTimeout <= TimeSpan.Zero)
            throw new ArgumentOutOfRangeException(nameof(options));
    }

    public async Task RunAsync(IReadOnlyList<RealtimeChannel> channels, RealtimeCredentials credentials,
        Func<CancellationToken, Task<RealtimeCredentials>> currentCredentials, Action onReady,
        Func<RealtimeChange, CancellationToken, Task> onChange, CancellationToken cancellationToken = default)
    {
        if (Interlocked.Exchange(ref started, 1) != 0) throw new InvalidOperationException("Realtime connections cannot be reused.");
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        Task? receiving = null;
        Task? dispatching = null;
        Task? heartbeats = null;
        Task? joining = null;
        try
        {
            await WithDeadlineAsync(async token =>
            {
                await transport.ConnectAsync(RealtimeProtocol.SocketEndpoint(credentials.ProjectUrl, credentials.AnonKey), credentials.AnonKey,
                    credentials.AccessToken, token).ConfigureAwait(false);
                return true;
            }, options.JoinTimeout, lifetime.Token).ConfigureAwait(false);
            receiving = ReceiveAsync(channels.ToDictionary(channel => channel.Topic, StringComparer.Ordinal), lifetime.Token);
            var pendingTasks = new List<Task>();
            foreach (var channel in channels)
            {
                var next = NextReference();
                var pending = new PendingJoin(channel, new(TaskCreationOptions.RunContinuationsAsynchronously));
                joins[next] = pending;
                joinReferences[channel.Topic] = next;
                pendingTasks.Add(pending.Completion.Task);
                await SendAsync(RealtimeProtocol.Join(channel, credentials.AccessToken, next), options.JoinTimeout, lifetime.Token).ConfigureAwait(false);
            }
            joining = Task.WhenAll(pendingTasks).WaitAsync(options.JoinTimeout, lifetime.Token);
            await await Task.WhenAny(joining, receiving).ConfigureAwait(false);
            if (receiving.IsCompleted) throw new RealtimeProtocolException("Realtime connection closed.");
            onReady();
            dispatching = DispatchAsync(onChange, lifetime.Token);
            heartbeats = HeartbeatAsync(credentials, currentCredentials, lifetime.Token);
            await await Task.WhenAny(receiving, dispatching, heartbeats).ConfigureAwait(false);
            throw new RealtimeProtocolException("Realtime connection closed.");
        }
        finally
        {
            lifetime.Cancel();
            foreach (var pending in joins.Values) pending.Completion.TrySetCanceled(lifetime.Token);
            changes.Writer.TryComplete();
            foreach (var task in new[] { receiving, dispatching, heartbeats, joining })
            {
                if (task is null) continue;
                try { await task.ConfigureAwait(false); }
                catch (Exception) { } // Observe every owned task without replacing the original failure.
            }
        }
    }

    private async Task ReceiveAsync(IReadOnlyDictionary<string, RealtimeChannel> channels, CancellationToken token)
    {
        while (true)
        {
            var text = await transport.ReceiveAsync(token).ConfigureAwait(false);
            if (text is null) throw new RealtimeProtocolException("Realtime connection closed.");
            var frame = RealtimeProtocol.Decode(text);
            if (frame.Event == "phx_reply")
            {
                if (frame.Reference is { } id && joins.TryGetValue(id, out var join) && frame.Topic == join.Channel.Topic)
                {
                    if (RealtimeProtocol.JoinAccepted(frame, join.Channel)) join.Completion.TrySetResult();
                    else join.Completion.TrySetException(new RealtimeProtocolException("Realtime subscription rejected."));
                }
                else if (Volatile.Read(ref heartbeat) is { } pending && frame.Topic == "phoenix" && frame.Reference == pending.Reference)
                {
                    if (RealtimeProtocol.String(frame.Payload, "status") == "ok") pending.Completion.TrySetResult();
                    else pending.Completion.TrySetException(new RealtimeProtocolException("Realtime heartbeat rejected."));
                }
                else if (channels.ContainsKey(frame.Topic) && RealtimeProtocol.String(frame.Payload, "status") == "error")
                    throw new RealtimeProtocolException("Realtime token update rejected.");
            }
            if (!channels.TryGetValue(frame.Topic, out var channel)) continue;
            if (frame.Event is "phx_error" or "phx_close" || (frame.Event == "system" && RealtimeProtocol.String(frame.Payload, "status") is "error" or "timeout"))
                throw new RealtimeProtocolException("Realtime channel unavailable.");
            if (RealtimeProtocol.Change(frame, channel) is { } change) changes.Writer.TryWrite(change);
        }
    }

    private async Task DispatchAsync(Func<RealtimeChange, CancellationToken, Task> onChange, CancellationToken token)
    {
        await foreach (var change in changes.Reader.ReadAllAsync(token).ConfigureAwait(false))
            await onChange(change, token).ConfigureAwait(false);
    }

    private async Task HeartbeatAsync(RealtimeCredentials initial, Func<CancellationToken, Task<RealtimeCredentials>> currentCredentials, CancellationToken token)
    {
        var lastToken = initial.AccessToken;
        while (true)
        {
            await Task.Delay(options.HeartbeatInterval, token).ConfigureAwait(false);
            var current = await WithDeadlineAsync(currentCredentials, options.JoinTimeout, token).ConfigureAwait(false);
            if (current.UserUid != initial.UserUid) throw new RealtimeIdentityChangedException();
            if (current.AccessToken != lastToken)
            {
                foreach (var (topic, joinRef) in joinReferences)
                    await SendAsync(RealtimeProtocol.Encode(topic, "access_token", new { access_token = current.AccessToken }, NextReference(), joinRef), options.HeartbeatTimeout, token).ConfigureAwait(false);
                lastToken = current.AccessToken;
            }
            var pending = new PendingHeartbeat(NextReference(), new(TaskCreationOptions.RunContinuationsAsynchronously));
            Volatile.Write(ref heartbeat, pending);
            await SendAsync(RealtimeProtocol.Encode("phoenix", "heartbeat", new { }, pending.Reference), options.HeartbeatTimeout, token).ConfigureAwait(false);
            await pending.Completion.Task.WaitAsync(options.HeartbeatTimeout, token).ConfigureAwait(false);
            Volatile.Write(ref heartbeat, null);
        }
    }

    private Task<bool> SendAsync(string text, TimeSpan timeout, CancellationToken token) => WithDeadlineAsync(async deadline =>
    {
        await transport.SendAsync(text, deadline).ConfigureAwait(false);
        return true;
    }, timeout, token);

    private static async Task<T> WithDeadlineAsync<T>(Func<CancellationToken, Task<T>> operation, TimeSpan timeout, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(timeout);
        try { return await operation(deadline.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested && deadline.IsCancellationRequested)
        { throw new TimeoutException("Realtime operation timed out."); }
    }

    private string NextReference() => Interlocked.Increment(ref reference).ToString(CultureInfo.InvariantCulture);
    private sealed record PendingJoin(RealtimeChannel Channel, TaskCompletionSource Completion);
    private sealed record PendingHeartbeat(string Reference, TaskCompletionSource Completion);
}
