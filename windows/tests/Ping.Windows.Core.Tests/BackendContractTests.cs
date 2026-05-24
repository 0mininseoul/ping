using System.Text.Json;
using System.Net;
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

    [Theory]
    [InlineData("\"seen\"", MessageStatus.Seen)]
    public void MessageStatusDecodesMacOSWireValues(string payload, MessageStatus expected)
    {
        Assert.Equal(expected, JsonSerializer.Deserialize<MessageStatus>(payload, JsonOptions.Supabase));
    }

    [Theory]
    [InlineData("\"open\"", RoomStatus.Open)]
    [InlineData("\"full\"", RoomStatus.Full)]
    public void RoomStatusDecodesMacOSWireValues(string payload, RoomStatus expected)
    {
        Assert.Equal(expected, JsonSerializer.Deserialize<RoomStatus>(payload, JsonOptions.Supabase));
    }

    [Fact]
    public async Task BootstrapWithoutSessionPostsAnonymousSignupAndSavesSession()
    {
        using var files = new SupabaseTestFiles();
        var handler = new RecordingHttpMessageHandler(request =>
        {
            Assert.Equal(HttpMethod.Post, request.Method);
            Assert.Equal("https://example.supabase.co/auth/v1/signup", request.RequestUri?.ToString());
            Assert.Equal("anon-key", request.Headers.GetValues("apikey").Single());
            Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
            Assert.Equal("anon-key", request.Headers.Authorization?.Parameter);

            return JsonResponse("""
                {
                  "access_token": "access-token",
                  "refresh_token": "refresh-token",
                  "expires_in": 3600,
                  "user": { "id": "user-id" }
                }
                """);
        });
        using var client = files.CreateClient(handler);

        var uid = await client.BootstrapAsync();

        Assert.Equal("user-id", uid);
        Assert.Single(handler.Requests);
        var saved = JsonSerializer.Deserialize<SupabaseSession>(await File.ReadAllTextAsync(files.SessionPath), JsonOptions.Supabase);
        Assert.Equal("access-token", saved?.AccessToken);
        Assert.Equal("refresh-token", saved?.RefreshToken);
        Assert.Equal("user-id", saved?.UserId);
    }

    [Fact]
    public async Task RpcValueUsesSavedAccessTokenAndJsonBody()
    {
        using var files = new SupabaseTestFiles();
        await files.SaveSessionAsync(new SupabaseSession(
            AccessToken: "access-token",
            RefreshToken: "refresh-token",
            ExpiresAt: DateTimeOffset.UtcNow.AddHours(1),
            UserId: "user-id"));
        var handler = new RecordingHttpMessageHandler(request =>
        {
            Assert.Equal(HttpMethod.Post, request.Method);
            Assert.Equal("https://example.supabase.co/rest/v1/rpc/ping_test", request.RequestUri?.ToString());
            Assert.Equal("anon-key", request.Headers.GetValues("apikey").Single());
            Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
            Assert.Equal("access-token", request.Headers.Authorization?.Parameter);
            Assert.Equal("application/json", request.Content?.Headers.ContentType?.MediaType);

            var body = request.Content?.ReadAsStringAsync().GetAwaiter().GetResult();
            Assert.Equal("""{"room_uuid":"room-id"}""", body);
            return JsonResponse("\"ok\"");
        });
        using var client = files.CreateClient(handler);

        var value = await client.RpcValueAsync<string>("ping_test", new { room_uuid = "room-id" });

        Assert.Equal("ok", value);
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task UploadObjectPostsPrivateStorageObjectWithMp4Contract()
    {
        using var files = new SupabaseTestFiles();
        await files.SaveSessionAsync(new SupabaseSession(
            AccessToken: "access-token",
            RefreshToken: "refresh-token",
            ExpiresAt: DateTimeOffset.UtcNow.AddHours(1),
            UserId: "user-id"));
        var localVideoPath = Path.Combine(files.DirectoryPath, "clip.mp4");
        await File.WriteAllBytesAsync(localVideoPath, [0x00, 0x01, 0x02]);
        var handler = new RecordingHttpMessageHandler(request =>
        {
            Assert.Equal(HttpMethod.Post, request.Method);
            Assert.Equal(
                "https://example.supabase.co/storage/v1/object/ping-videos/sender%20uid/video%20id.mp4",
                request.RequestUri?.ToString());
            Assert.Equal("anon-key", request.Headers.GetValues("apikey").Single());
            Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
            Assert.Equal("access-token", request.Headers.Authorization?.Parameter);
            Assert.Equal("true", request.Headers.GetValues("x-upsert").Single());
            Assert.Equal("video/mp4", request.Content?.Headers.ContentType?.MediaType);
            Assert.Equal([0x00, 0x01, 0x02], request.Content?.ReadAsByteArrayAsync().GetAwaiter().GetResult());
            return JsonResponse("{}");
        });
        using var client = files.CreateClient(handler);

        await client.UploadObjectAsync("ping-videos", "sender uid/video id.mp4", localVideoPath, "video/mp4");

        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task ExpiredStoredSessionRefreshFailureThrowsDomainExceptionWithoutSignup()
    {
        using var files = new SupabaseTestFiles();
        await files.SaveSessionAsync(new SupabaseSession(
            AccessToken: "old-access-token",
            RefreshToken: "expired-refresh-token",
            ExpiresAt: DateTimeOffset.UtcNow.AddMinutes(-5),
            UserId: "user-id"));
        var handler = new RecordingHttpMessageHandler(request =>
        {
            Assert.Equal("https://example.supabase.co/auth/v1/token?grant_type=refresh_token", request.RequestUri?.ToString());
            return JsonResponse("""{"message":"Invalid Refresh Token"}""", HttpStatusCode.Unauthorized);
        });
        using var client = files.CreateClient(handler);

        var exception = await Assert.ThrowsAsync<SupabaseSessionExpiredException>(
            () => client.BootstrapAsync());

        Assert.Equal("user-id", exception.UserId);
        Assert.Single(handler.Requests);
        Assert.DoesNotContain(handler.Requests, request => request.RequestUri?.AbsolutePath.EndsWith("/signup", StringComparison.Ordinal) == true);
        var saved = JsonSerializer.Deserialize<SupabaseSession>(await File.ReadAllTextAsync(files.SessionPath), JsonOptions.Supabase);
        Assert.Equal("user-id", saved?.UserId);
        Assert.Equal("expired-refresh-token", saved?.RefreshToken);
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

    private static HttpResponseMessage JsonResponse(string json, HttpStatusCode statusCode = HttpStatusCode.OK)
    {
        return new HttpResponseMessage(statusCode)
        {
            Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json")
        };
    }

    private sealed class RecordingHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        public List<HttpRequestMessage> Requests { get; } = [];

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request);
            return Task.FromResult(responder(request));
        }
    }

    private sealed class SupabaseTestFiles : IDisposable
    {
        public SupabaseTestFiles()
        {
            DirectoryPath = Path.Combine(Path.GetTempPath(), "PingWindowsTests", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(DirectoryPath);
            ConfigPath = Path.Combine(DirectoryPath, "Supabase.json");
            SessionPath = Path.Combine(DirectoryPath, "SupabaseSession.json");
            File.WriteAllText(
                ConfigPath,
                """
                {
                  "SUPABASE_URL": "https://example.supabase.co",
                  "SUPABASE_ANON_KEY": "anon-key"
                }
                """);
        }

        public string DirectoryPath { get; }

        public string ConfigPath { get; }

        public string SessionPath { get; }

        public SupabaseClient CreateClient(HttpMessageHandler handler)
        {
            return new SupabaseClient(new HttpClient(handler), ConfigPath, SessionPath);
        }

        public async Task SaveSessionAsync(SupabaseSession session)
        {
            await File.WriteAllTextAsync(SessionPath, JsonSerializer.Serialize(session, JsonOptions.Supabase));
        }

        public void Dispose()
        {
            Directory.Delete(DirectoryPath, recursive: true);
        }
    }
}
