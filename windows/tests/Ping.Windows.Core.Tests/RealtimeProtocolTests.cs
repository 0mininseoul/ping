using System.Text.Json;
using Ping.Windows.Core.Realtime;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class RealtimeProtocolTests
{
    [Fact]
    public void EndpointExplicitlySelectsSupportedObjectProtocol()
    {
        var endpoint = RealtimeProtocol.SocketEndpoint(new Uri("https://example.supabase.co"), "public key&x");
        Assert.Equal("wss", endpoint.Scheme);
        Assert.Equal("/realtime/v1/websocket", endpoint.AbsolutePath);
        Assert.Contains("apikey=public%20key%26x", endpoint.Query);
        Assert.Contains("vsn=1.0.0", endpoint.Query);
    }

    [Fact]
    public void JoinIncludesCurrentTokenAndExactReceiverRoomFilters()
    {
        var channels = RealtimeProtocol.Channels("me", ["b", "a", "a"]);
        Assert.Equal(3, channels.Count);
        var incoming = Assert.Single(channels, channel => channel.Filters.Any(filter => filter.Table == "messages"));
        Assert.Equal("receiver_uid=eq.me", Assert.Single(incoming.Filters).Filter);
        var room = Assert.Single(channels, channel => channel.Topic == "realtime:chat-room-a");
        Assert.All(room.Filters, filter => Assert.Equal("room_id=eq.a", filter.Filter));
        using var json = JsonDocument.Parse(RealtimeProtocol.Join(room, "fresh-token", "7"));
        Assert.Equal("fresh-token", json.RootElement.GetProperty("payload").GetProperty("access_token").GetString());
        Assert.Equal("phx_join", json.RootElement.GetProperty("event").GetString());
        Assert.Equal("7", json.RootElement.GetProperty("join_ref").GetString());
    }

    [Fact]
    public void DeleteWithoutRoomMetadataKeepsSafeChannelScope()
    {
        var channel = RealtimeProtocol.Channels("me", ["room"]).Single(channel => channel.Topic == "realtime:chat-room-room");
        var frame = RealtimeProtocol.Decode("""{"event":"postgres_changes","topic":"realtime:chat-room-room","payload":{"data":{"schema":"public","table":"chat_messages","type":"DELETE","old_record":{"id":"gone"}}}}""");
        var change = RealtimeProtocol.Change(frame, channel);
        Assert.NotNull(change);
        Assert.Equal("room", change.RoomId);
        Assert.Equal("gone", change.ItemId);
        Assert.Equal(RealtimeChangeKind.Chat, change.Kind);
    }

    [Theory]
    [InlineData("not-json")]
    [InlineData("[]")]
    [InlineData("{\"event\":7}")]
    public void InvalidFrameFailsWithSanitizedDiagnostic(string payload)
    {
        var error = Assert.Throws<RealtimeProtocolException>(() => RealtimeProtocol.Decode(payload));
        Assert.Equal("Invalid Realtime frame.", error.Message);
        Assert.Null(error.InnerException);
    }

    [Fact]
    public void UnsubscribedTablesAndWrongRoomRecordsAreIgnored()
    {
        var channel = RealtimeProtocol.Channels("me", ["room"]).Single(channel => channel.Topic == "realtime:chat-room-room");
        var frame = RealtimeProtocol.Decode("""{"event":"postgres_changes","topic":"realtime:chat-room-room","payload":{"data":{"schema":"public","table":"chat_messages","type":"INSERT","record":{"room_id":"another","id":"id"}}}}""");
        Assert.Null(RealtimeProtocol.Change(frame, channel));
    }

    [Fact]
    public void JoinAcceptanceRequiresSubscribedTablesRatherThanSocketOpen()
    {
        var channel = RealtimeProtocol.Channels("me", []).Single();
        var rejected = RealtimeProtocol.Decode("""{"event":"phx_reply","topic":"topic","ref":"1","payload":{"status":"ok","response":{"postgres_changes":[]}}}""");
        Assert.False(RealtimeProtocol.JoinAccepted(rejected, channel));
        var accepted = RealtimeProtocol.Decode("""{"event":"phx_reply","topic":"topic","ref":"1","payload":{"status":"ok","response":{"postgres_changes":[{"id":123,"schema":"public","table":"messages","event":"INSERT"}]}}}""");
        Assert.True(RealtimeProtocol.JoinAccepted(accepted, channel));
    }
}
