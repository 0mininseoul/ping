using System.Text.Json;
using System.Net;
using Ping.Windows.Core.Backend;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class AutoReplyContractTests
{
    [Fact]
    public async Task GroupReplyUploadsForOneOriginalSenderAndUsesMacWirePosition()
    {
        var rpc = new Rpc();
        var storage = new Storage();
        var input = Input();
        Assert.True(await new MessageService(rpc, storage).SendAutoReplyAsync(input, () => true));
        Assert.Equal(new[] { "peer" }, storage.Recipients);
        Assert.Equal("me", storage.Sender);
        Assert.Equal("ping_create_message", rpc.Function);
        using var json = JsonDocument.Parse(JsonSerializer.Serialize(rpc.Body, JsonOptions.Supabase));
        var body = json.RootElement;
        Assert.Equal("group", body.GetProperty("room_uuid").GetString());
        Assert.Equal("peer", body.GetProperty("receiver_uid").GetString());
        Assert.True(body.GetProperty("is_auto_reply_value").GetBoolean());
        Assert.True(body.GetProperty("allows_local_save_value").GetBoolean());
        Assert.Equal("face_only", body.GetProperty("capture_mode_text").GetString());
        Assert.Equal(1, body.GetProperty("aspect_ratio_value").GetDouble());
        Assert.Equal(.25, body.GetProperty("x_ratio").GetDouble());
        Assert.Equal(.8, body.GetProperty("y_ratio").GetDouble());
        Assert.Equal(1, rpc.Count);
        Assert.Empty(storage.Deleted);
    }

    [Fact]
    public async Task ExpiredPermissionAfterUploadDeletesClipWithoutCreatingMessage()
    {
        var rpc = new Rpc();
        var storage = new Storage();
        var checks = 0;
        Assert.False(await new MessageService(rpc, storage).SendAutoReplyAsync(Input(), () => ++checks == 1));
        Assert.Equal(0, rpc.Count);
        Assert.Equal(new[] { "me/reply.mp4" }, storage.Deleted);
    }

    [Fact]
    public async Task CreateFailureCleansUnusedUploadedObject()
    {
        var rpc = new Rpc { Failure = new SupabaseRequestException(HttpStatusCode.Forbidden, [], null) };
        var storage = new Storage();
        await Assert.ThrowsAsync<SupabaseRequestException>(() => new MessageService(rpc, storage).SendAutoReplyAsync(Input(), () => true));
        Assert.Equal(new[] { "me/reply.mp4" }, storage.Deleted);
    }

    [Fact]
    public async Task LostCreateResponseCannotDeleteClipThatServerMayAlreadyReference()
    {
        var rpc = new Rpc { Failure = new IOException("response lost after server may have committed") };
        var storage = new Storage();
        await Assert.ThrowsAsync<IOException>(() => new MessageService(rpc, storage).SendAutoReplyAsync(Input(), () => true));
        Assert.Equal(1, rpc.Count);
        Assert.Empty(storage.Deleted);
    }

    [Fact]
    public async Task InvalidReplyCannotUpload()
    {
        var rpc = new Rpc();
        var storage = new Storage();
        var service = new MessageService(rpc, storage);
        var original = Input().OriginalMessage;
        foreach (var video in new[] { original with { IsAutoReply = true }, original with { SenderUid = "me" }, original with { ReceiverUid = "other" } })
            await Assert.ThrowsAsync<ArgumentException>(() => service.SendAutoReplyAsync(Input() with { OriginalMessage = video }, () => true));
        Assert.Equal(0, storage.Uploads);
        Assert.False(await service.SendAutoReplyAsync(Input(), () => false));
        Assert.Equal(0, storage.Uploads);
    }

    private static AutoReplyVideoInput Input() => new(AutoFaceReplyPolicyTests.Video(), "owned-reply.mp4", "me", "Me", true);

    private sealed class Storage : IStorageService
    {
        public string[] Recipients = [];
        public string? Sender;
        public int Uploads;
        public List<string> Deleted = [];
        public Task<string> UploadVideoAsync(string path, string sender, string id, IReadOnlyCollection<string> recipients,
            DateTimeOffset expires, CancellationToken cancellationToken = default)
        {
            ++Uploads;
            Sender = sender;
            Recipients = recipients.ToArray();
            Assert.Equal("owned-reply.mp4", path);
            Assert.True(Guid.TryParse(id, out _));
            Assert.InRange(expires, DateTimeOffset.UtcNow.AddDays(29), DateTimeOffset.UtcNow.AddDays(31));
            return Task.FromResult("me/reply.mp4");
        }
        public Task DeleteVideoAsync(string path, CancellationToken cancellationToken = default) { Deleted.Add(path); return Task.CompletedTask; }
    }

    private sealed class Rpc : ISupabaseRpcClient
    {
        public string? Function;
        public object? Body;
        public int Count;
        public Exception? Failure;
        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            ++Count;
            Function = function;
            Body = body;
            return Failure is { } failure ? Task.FromException<T>(failure) : Task.FromResult((T)(object)"reply-message");
        }
        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default) => throw new NotSupportedException();
    }
}
