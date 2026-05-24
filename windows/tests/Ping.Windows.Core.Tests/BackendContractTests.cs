using System.Text.Json;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class BackendContractTests
{
    [Fact]
    public void CaptureModeWireValuesMatchMacOS()
    {
        Assert.Equal("face_only", CaptureMode.FaceOnly.ToWireValue());
        Assert.Equal("screen_face", CaptureMode.ScreenFace.ToWireValue());
        Assert.Equal(CaptureMode.ScreenFace, CaptureModeWire.Parse("screen_face"));
    }

    [Fact]
    public void VideoMessageDecodesMacOSPayload()
    {
        const string payload = """
            {
              "id": "message-1",
              "room_id": "room-1",
              "sender_uid": "sender-1",
              "receiver_uid": "receiver-1",
              "sender_nickname": "Youngmin",
              "video_id": "video-1",
              "video_url": "sender-1/video-1.mp4",
              "duration_ms": 3000,
              "mirror_position": { "xRatio": 0.25, "yRatio": 0.75 },
              "status": "uploaded",
              "created_at": "2026-05-24T12:34:56Z",
              "expires_at": "2026-05-25T12:34:56Z",
              "capture_mode": "screen_face",
              "aspect_ratio": 1.7777778,
              "allows_local_save": true
            }
            """;

        var message = JsonSerializer.Deserialize<VideoMessage>(payload, JsonOptions.Supabase)
            ?? throw new InvalidOperationException("VideoMessage payload did not deserialize.");
        Assert.Equal("message-1", message.Id);
        Assert.Equal("room-1", message.RoomId);
        Assert.Equal("sender-1", message.SenderUid);
        Assert.Equal("receiver-1", message.ReceiverUid);
        Assert.Equal("Youngmin", message.SenderNickname);
        Assert.Equal("video-1", message.VideoId);
        Assert.Equal("sender-1/video-1.mp4", message.VideoUrl);
        Assert.Equal(3000, message.DurationMs);
        Assert.Equal(0.25, message.MirrorPosition.XRatio);
        Assert.Equal(0.75, message.MirrorPosition.YRatio);
        Assert.Equal(MessageStatus.Uploaded, message.Status);
        Assert.Equal(CaptureMode.ScreenFace, message.CaptureMode);
        Assert.Equal(1.7777778, message.AspectRatio);
        Assert.True(message.AllowsLocalSave);
    }

    [Fact]
    public void MessageServiceUsesMacOSCreateMessageRpcBody()
    {
        var rpc = new RecordingRpcClient();
        var storage = new StubStorageService("sender-uid/shared-video-id.mp4");
        var service = new MessageService(rpc, storage);
        var input = new SendVideoInput(
            Rooms:
            [
                new Room(
                    Id: "room-id",
                    Name: "Room",
                    SearchableName: "room",
                    OwnerUid: "sender-uid",
                    MemberUids: ["sender-uid", "receiver-uid"],
                    MemberNicknames: new Dictionary<string, string>
                    {
                        ["sender-uid"] = "Youngmin",
                        ["receiver-uid"] = "Receiver"
                    },
                    Status: RoomStatus.Open)
            ],
            LocalVideoPath: "/tmp/ping.mp4",
            MirrorPosition: new MirrorPosition(0.5, 0.5),
            SenderUid: "sender-uid",
            SenderNickname: "Youngmin",
            CaptureMode: CaptureMode.ScreenFace,
            AspectRatio: 1.7777778,
            AllowsLocalSave: false,
            SharedVideoId: "shared-video-id");

        service.SendAsync(input).GetAwaiter().GetResult();

        Assert.Equal("ping_create_message", rpc.Calls.Single().Function);
        Assert.Equal(
            """
            {"room_uuid":"room-id","receiver_uid":"receiver-uid","sender_nickname_text":"Youngmin","video_id_text":"shared-video-id","video_url_text":"sender-uid/shared-video-id.mp4","x_ratio":0.5,"y_ratio":0.5,"capture_mode_text":"screen_face","aspect_ratio_value":1.7777778,"allows_local_save_value":false}
            """,
            JsonSerializer.Serialize(rpc.Calls.Single().Body, JsonOptions.Supabase));
    }

    private sealed class RecordingRpcClient : ISupabaseRpcClient
    {
        public List<(string Function, object Body)> Calls { get; } = [];

        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            Calls.Add((function, body ?? new { }));
            object value = "message-id";
            return Task.FromResult((T)value);
        }

        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            Calls.Add((function, body ?? new { }));
            return Task.CompletedTask;
        }
    }

    private sealed class StubStorageService(string storagePath) : IStorageService
    {
        public Task<string> UploadVideoAsync(
            string localVideoPath,
            string senderUid,
            string videoId,
            IReadOnlyCollection<string> authorizedReceiverUids,
            DateTimeOffset expiresAt,
            CancellationToken cancellationToken = default)
        {
            Assert.Equal("/tmp/ping.mp4", localVideoPath);
            Assert.Equal("sender-uid", senderUid);
            Assert.Equal("shared-video-id", videoId);
            Assert.Equal(new[] { "receiver-uid" }, authorizedReceiverUids);
            return Task.FromResult(storagePath);
        }
    }
}
