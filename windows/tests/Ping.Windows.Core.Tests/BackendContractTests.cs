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

    [Fact]
    public void SupabaseConfigurationAcceptsWindowsSetupJsonAliases()
    {
        var config = JsonSerializer.Deserialize<SupabaseConfiguration>(
            """
            {
              "url": "https://example.supabase.co",
              "anonKey": "anon-key"
            }
            """,
            JsonOptions.Supabase)?.Normalize();

        Assert.NotNull(config);
        Assert.Equal("https://example.supabase.co/", config.Url.ToString());
        Assert.Equal("anon-key", config.AnonKey);
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
                request.RequestUri?.AbsoluteUri);
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
    public async Task DownloadObjectGetsPrivateStorageObject()
    {
        using var files = new SupabaseTestFiles();
        await files.SaveSessionAsync(new SupabaseSession(
            AccessToken: "access-token",
            RefreshToken: "refresh-token",
            ExpiresAt: DateTimeOffset.UtcNow.AddHours(1),
            UserId: "user-id"));
        var handler = new RecordingHttpMessageHandler(request =>
        {
            Assert.Equal(HttpMethod.Get, request.Method);
            Assert.Equal(
                "https://example.supabase.co/storage/v1/object/ping-videos/sender%20uid/video%20id.mp4",
                request.RequestUri?.AbsoluteUri);
            Assert.Equal("anon-key", request.Headers.GetValues("apikey").Single());
            Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
            Assert.Equal("access-token", request.Headers.Authorization?.Parameter);
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([0x00, 0x01, 0x02])
            };
        });
        using var client = files.CreateClient(handler);
        var localPath = Path.Combine(files.DirectoryPath, "download.mp4");

        await client.DownloadObjectAsync("ping-videos", "sender uid/video id.mp4", localPath);

        Assert.Equal([0x00, 0x01, 0x02], await File.ReadAllBytesAsync(localPath));
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task StorageServiceUploadsAndDownloadsChatImagesWithMacContract()
    {
        using var files = new SupabaseTestFiles();
        await files.SaveSessionAsync(new SupabaseSession(
            AccessToken: "access-token",
            RefreshToken: "refresh-token",
            ExpiresAt: DateTimeOffset.UtcNow.AddHours(1),
            UserId: "user-id"));
        var localImagePath = Path.Combine(files.DirectoryPath, "message.png");
        await File.WriteAllBytesAsync(localImagePath, [0x89, 0x50, 0x4E, 0x47]);
        var requestIndex = 0;
        var handler = new RecordingHttpMessageHandler(request =>
        {
            requestIndex++;
            Assert.Equal("anon-key", request.Headers.GetValues("apikey").Single());
            Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
            Assert.Equal("access-token", request.Headers.Authorization?.Parameter);

            if (requestIndex == 1)
            {
                Assert.Equal(HttpMethod.Post, request.Method);
                Assert.Equal(
                    "https://example.supabase.co/storage/v1/object/ping-media/sender-uid/chat-images/message-id.png",
                    request.RequestUri?.ToString());
                Assert.Equal("true", request.Headers.GetValues("x-upsert").Single());
                Assert.Equal("image/png", request.Content?.Headers.ContentType?.MediaType);
                Assert.Equal([0x89, 0x50, 0x4E, 0x47], request.Content?.ReadAsByteArrayAsync().GetAwaiter().GetResult());
                return JsonResponse("{}");
            }

            Assert.Equal(HttpMethod.Get, request.Method);
            Assert.Equal(
                "https://example.supabase.co/storage/v1/object/ping-media/sender-uid/chat-images/message-id.png",
                request.RequestUri?.ToString());
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent([0x01, 0x02, 0x03])
            };
        });
        using var client = files.CreateClient(handler);
        var service = new StorageService(client);

        var upload = await service.UploadChatImageAsync(localImagePath, "sender-uid", "message-id");
        var downloaded = await service.DownloadChatMediaAsync(upload.Path, "png");

        Assert.Equal("sender-uid/chat-images/message-id.png", upload.Path);
        Assert.Equal("image/png", upload.MimeType);
        Assert.Equal("message.png", upload.FileName);
        Assert.Equal([0x01, 0x02, 0x03], await File.ReadAllBytesAsync(downloaded));
        Assert.Equal(2, handler.Requests.Count);
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
    public async Task CorruptStoredSessionFallsBackToAnonymousSignup()
    {
        using var files = new SupabaseTestFiles();
        await File.WriteAllTextAsync(files.SessionPath, "{not-json");
        var handler = new RecordingHttpMessageHandler(request =>
        {
            Assert.Equal("https://example.supabase.co/auth/v1/signup", request.RequestUri?.ToString());
            return JsonResponse("""
                {
                  "access_token": "new-access-token",
                  "refresh_token": "new-refresh-token",
                  "expires_in": 3600,
                  "user": { "id": "new-user-id" }
                }
                """);
        });
        using var client = files.CreateClient(handler);

        var uid = await client.BootstrapAsync();

        Assert.Equal("new-user-id", uid);
        Assert.Single(handler.Requests);
        var saved = JsonSerializer.Deserialize<SupabaseSession>(await File.ReadAllTextAsync(files.SessionPath), JsonOptions.Supabase);
        Assert.Equal("new-refresh-token", saved?.RefreshToken);
    }

    [Fact]
    public async Task MessageServiceUsesMacOSCreateMessageRpcBody()
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

        await service.SendAsync(input);

        Assert.Equal("ping_create_message", rpc.Calls.Single().Function);
        Assert.Equal(
            """
            {"room_uuid":"room-id","receiver_uid":"receiver-uid","sender_nickname_text":"Youngmin","video_id_text":"shared-video-id","video_url_text":"sender-uid/shared-video-id.mp4","x_ratio":0.5,"y_ratio":0.5,"capture_mode_text":"screen_face","aspect_ratio_value":1.7777778,"allows_local_save_value":false}
            """,
            JsonSerializer.Serialize(rpc.Calls.Single().Body, JsonOptions.Supabase));
    }

    [Fact]
    public async Task MessageServiceUsesMacOSIncomingPlaybackRpcBodies()
    {
        var rpc = new RecordingIncomingRpcClient();
        var service = new MessageService(rpc, new StubStorageService("sender-uid/shared-video-id.mp4"));

        var incoming = await service.IncomingAsync();
        var message = await service.GetAsync("message-id");
        await service.MarkSeenAsync("message-id");
        var roomMessages = await service.RoomMessagesAsync("room-id", limit: 25);
        await service.DeleteMessageAsync("message-id");
        await service.HideMessageForReceiverAsync("message-id");

        Assert.Single(incoming);
        Assert.Equal("message-id", message?.Id);
        Assert.Single(roomMessages);
        Assert.Equal("ping_incoming_messages", rpc.Calls[0].Function);
        Assert.Equal("ping_get_message", rpc.Calls[1].Function);
        Assert.Equal(
            """
            {"message_uuid":"message-id"}
            """,
            JsonSerializer.Serialize(rpc.Calls[1].Body, JsonOptions.Supabase));
        Assert.Equal("ping_mark_message_seen", rpc.Calls[2].Function);
        Assert.Equal(
            """
            {"message_uuid":"message-id"}
            """,
            JsonSerializer.Serialize(rpc.Calls[2].Body, JsonOptions.Supabase));
        Assert.Equal("ping_room_messages", rpc.Calls[3].Function);
        Assert.Equal(
            """
            {"room_uuid":"room-id","before_ts":null,"page_limit":25}
            """,
            JsonSerializer.Serialize(rpc.Calls[3].Body, JsonOptions.Supabase));
        Assert.Equal("ping_delete_message", rpc.Calls[4].Function);
        Assert.Equal(
            """
            {"message_uuid":"message-id"}
            """,
            JsonSerializer.Serialize(rpc.Calls[4].Body, JsonOptions.Supabase));
        Assert.Equal("ping_hide_message_for_receiver", rpc.Calls[5].Function);
        Assert.Equal(
            """
            {"message_uuid":"message-id"}
            """,
            JsonSerializer.Serialize(rpc.Calls[5].Body, JsonOptions.Supabase));
    }

    [Fact]
    public async Task UserServiceUsesMacOSProfileRpcBodies()
    {
        var rpc = new RecordingProfileRpcClient();
        var service = new UserService(rpc);

        var profile = await service.GetAsync("sender-uid");
        await service.UpdateLastUsedRoomAsync("room-id");

        Assert.Equal("room-id", profile?.LastUsedRoomId);
        Assert.Equal(
            """
            {"target_uid":"sender-uid"}
            """,
            JsonSerializer.Serialize(rpc.Calls[0].Body, JsonOptions.Supabase));
        Assert.Equal("ping_get_profile", rpc.Calls[0].Function);
        Assert.Equal("ping_update_last_used_room", rpc.Calls[1].Function);
        Assert.Equal(
            """
            {"room_uuid":"room-id"}
            """,
            JsonSerializer.Serialize(rpc.Calls[1].Body, JsonOptions.Supabase));
    }

    [Fact]
    public async Task CleanupServiceCallsSharedCleanupRpc()
    {
        var rpc = new RecordingRpcClient();
        var service = new CleanupService(rpc);

        await service.RunAsync();

        Assert.Equal("ping_cleanup_expired_data", Assert.Single(rpc.Calls).Function);
    }

    [Fact]
    public async Task StorageServiceRejectsInvalidUploadPayloadsBeforeNetwork()
    {
        using var files = new SupabaseTestFiles();
        using var client = files.CreateClient(new RecordingHttpMessageHandler(_ => throw new InvalidOperationException("network")));
        var service = new StorageService(client);
        var emptyMp4 = Path.Combine(files.DirectoryPath, "empty.mp4");
        var textFile = Path.Combine(files.DirectoryPath, "clip.txt");
        await File.WriteAllBytesAsync(emptyMp4, []);
        await File.WriteAllTextAsync(textFile, "not video");

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => service.UploadVideoAsync(emptyMp4, "sender-uid", "video-id", ["receiver"], DateTimeOffset.UtcNow));
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.UploadVideoAsync(textFile, "sender-uid", "video-id", ["receiver"], DateTimeOffset.UtcNow));
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.UploadVideoAsync(emptyMp4, "sender/uid", "video-id", ["receiver"], DateTimeOffset.UtcNow));
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.DownloadVideoAsync("sender-uid/video-id.mov"));
        await Assert.ThrowsAsync<InvalidOperationException>(
            () => service.UploadChatImageAsync(emptyMp4, "sender-uid", "message-id"));
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.UploadChatImageAsync(textFile, "sender-uid", "message-id"));
        await Assert.ThrowsAsync<ArgumentException>(
            () => service.DownloadChatMediaAsync("../sender/chat-images/message.png", "png"));
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

    private sealed class RecordingProfileRpcClient : ISupabaseRpcClient
    {
        public List<(string Function, object Body)> Calls { get; } = [];

        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            Calls.Add((function, body ?? new { }));
            object result = new[]
            {
                new PingUser(
                    Id: "sender-uid",
                    Nickname: "Youngmin",
                    SearchableNickname: "youngmin",
                    Rooms: ["room-id"],
                    LastUsedRoomId: "room-id")
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }

        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
        }

        public Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            Calls.Add((function, body ?? new { }));
            return Task.CompletedTask;
        }
    }

    private sealed class RecordingIncomingRpcClient : ISupabaseRpcClient
    {
        public List<(string Function, object Body)> Calls { get; } = [];

        public Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            Calls.Add((function, body ?? new { }));
            object result = new[]
            {
                new VideoMessage
                {
                    Id = "message-id",
                    RoomId = "room-id",
                    SenderUid = "sender-uid",
                    ReceiverUid = "receiver-uid",
                    SenderNickname = "Youngmin",
                    VideoId = "video-id",
                    VideoUrl = "sender-uid/video-id.mp4",
                    DurationMs = 3000,
                    MirrorPosition = new MirrorPosition(0.5, 0.5),
                    Status = MessageStatus.Uploaded,
                    CreatedAt = DateTimeOffset.UtcNow,
                    ExpiresAt = DateTimeOffset.UtcNow.AddDays(1)
                }
            };
            return Task.FromResult((IReadOnlyList<T>)result);
        }

        public Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
        {
            throw new NotSupportedException();
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
