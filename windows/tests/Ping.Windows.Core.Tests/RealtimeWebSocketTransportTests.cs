using System.Net.WebSockets;
using System.Text;
using Ping.Windows.Core.Realtime;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class RealtimeWebSocketTransportTests
{
    [Fact]
    public async Task FragmentedUtf8FramesAreReassembledBeforeDecoding()
    {
        var text = "안녕하세요";
        var bytes = Encoding.UTF8.GetBytes(text);
        using var socket = new ScriptedSocket([(bytes[..4], WebSocketMessageType.Text, false), (bytes[4..], WebSocketMessageType.Text, true)]);
        await using var transport = new RealtimeWebSocketTransport(socket);
        Assert.Equal(text, await transport.ReceiveAsync(CancellationToken.None));
    }

    [Fact]
    public async Task BinaryFramesAndOversizedMessagesAreRejected()
    {
        using var binary = new ScriptedSocket([([1], WebSocketMessageType.Binary, true)]);
        await using var binaryTransport = new RealtimeWebSocketTransport(binary);
        await Assert.ThrowsAsync<RealtimeProtocolException>(() => binaryTransport.ReceiveAsync(CancellationToken.None));
        using var large = new ScriptedSocket([(new byte[9], WebSocketMessageType.Text, true)]);
        await using var bounded = new RealtimeWebSocketTransport(large, maximumMessageBytes: 8);
        await Assert.ThrowsAsync<RealtimeProtocolException>(() => bounded.ReceiveAsync(CancellationToken.None));
    }

    [Fact]
    public async Task CloseFrameTerminatesReceiveAndDisposalAbortsOwnedSocket()
    {
        using var socket = new ScriptedSocket([([], WebSocketMessageType.Close, true)]);
        var transport = new RealtimeWebSocketTransport(socket);
        Assert.Null(await transport.ReceiveAsync(CancellationToken.None));
        await transport.DisposeAsync();
        Assert.True(socket.Aborted);
    }

    private sealed class ScriptedSocket(IReadOnlyList<(byte[] Bytes, WebSocketMessageType Type, bool End)> frames) : WebSocket
    {
        private int next;
        public bool Aborted;
        public override WebSocketCloseStatus? CloseStatus => null;
        public override string? CloseStatusDescription => null;
        public override WebSocketState State => Aborted ? WebSocketState.Aborted : WebSocketState.Open;
        public override string? SubProtocol => null;
        public override void Abort() => Aborted = true;
        public override void Dispose() { }
        public override Task CloseAsync(WebSocketCloseStatus status, string? description, CancellationToken token) => Task.CompletedTask;
        public override Task CloseOutputAsync(WebSocketCloseStatus status, string? description, CancellationToken token) => Task.CompletedTask;
        public override Task SendAsync(ArraySegment<byte> buffer, WebSocketMessageType type, bool end, CancellationToken token) => Task.CompletedTask;
        public override Task<WebSocketReceiveResult> ReceiveAsync(ArraySegment<byte> buffer, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            var frame = frames[next++];
            frame.Bytes.CopyTo(buffer.AsSpan());
            return Task.FromResult(new WebSocketReceiveResult(frame.Bytes.Length, frame.Type, frame.End));
        }
    }
}
