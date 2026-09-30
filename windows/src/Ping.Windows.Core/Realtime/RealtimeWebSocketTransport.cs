using System.Net.WebSockets;
using System.Text;

namespace Ping.Windows.Core.Realtime;

public sealed class RealtimeWebSocketTransport : IRealtimeTransport
{
    public const int MaximumMessageBytes = 256 * 1024;
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private readonly WebSocket socket;
    private readonly int maximumMessageBytes;
    private readonly SemaphoreSlim sending = new(1, 1);
    private int disposed;

    public RealtimeWebSocketTransport() : this(new ClientWebSocket()) { }

    public RealtimeWebSocketTransport(WebSocket socket, int maximumMessageBytes = MaximumMessageBytes)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximumMessageBytes);
        this.socket = socket;
        this.maximumMessageBytes = maximumMessageBytes;
    }

    public async Task ConnectAsync(Uri endpoint, string anonKey, string token, CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        if (socket is not ClientWebSocket client) throw new InvalidOperationException("Only a client WebSocket can initiate a connection.");
        client.Options.SetRequestHeader("apikey", anonKey);
        client.Options.SetRequestHeader("Authorization", "Bearer " + token);
        client.Options.KeepAliveInterval = TimeSpan.Zero;
        await client.ConnectAsync(endpoint, cancellationToken).ConfigureAwait(false);
    }

    public async Task SendAsync(string text, CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        var bytes = Utf8.GetBytes(text);
        await sending.WaitAsync(cancellationToken).ConfigureAwait(false);
        try { await socket.SendAsync(bytes.AsMemory(), WebSocketMessageType.Text, true, cancellationToken).ConfigureAwait(false); }
        finally { sending.Release(); }
    }

    public async Task<string?> ReceiveAsync(CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref disposed) != 0, this);
        using var content = new MemoryStream();
        var buffer = new byte[4096];
        while (true)
        {
            var frame = await socket.ReceiveAsync(buffer.AsMemory(), cancellationToken).ConfigureAwait(false);
            if (frame.MessageType == WebSocketMessageType.Close) return null;
            if (frame.MessageType != WebSocketMessageType.Text || content.Length + frame.Count > maximumMessageBytes)
                throw new RealtimeProtocolException("Realtime frame type or size is invalid.");
            content.Write(buffer, 0, frame.Count);
            if (!frame.EndOfMessage) continue;
            try { return Utf8.GetString(content.GetBuffer(), 0, (int)content.Length); }
            catch (DecoderFallbackException) { throw new RealtimeProtocolException(); }
        }
    }

    public ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref disposed, 1) == 0)
        {
            socket.Abort();
            socket.Dispose();
        }
        return ValueTask.CompletedTask;
    }
}
