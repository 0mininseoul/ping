using System.Net;
using System.Text.Json;
using Ping.Windows.Core.Backend;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class SessionRecoveryTests
{
    [Theory]
    [InlineData(408)]
    [InlineData(429)]
    [InlineData(500)]
    [InlineData(503)]
    public async Task TemporaryRefreshFailurePreservesAccountAndHttpStatus(int status)
    {
        using var fixture = new SessionFixture();
        await fixture.WriteExpiredSessionAsync();
        var original = await File.ReadAllTextAsync(fixture.SessionPath);
        using var http = new HttpClient(new Handler(_ => new HttpResponseMessage((HttpStatusCode)status)
        {
            Content = new StringContent("""{"code":"unexpected_failure","message":"Temporary failure"}""")
        }));
        using var client = fixture.Client(http);

        var error = await Record.ExceptionAsync(() => client.BootstrapAsync());

        var requestError = Assert.IsAssignableFrom<HttpRequestException>(error);
        Assert.Equal((HttpStatusCode)status, requestError.StatusCode);
        Assert.Equal(original, await File.ReadAllTextAsync(fixture.SessionPath));
        Assert.Equal("existing-user", client.CurrentUid);
    }

    [Fact]
    public async Task NetworkFailureCanRecoverWithSameStoredIdentity()
    {
        using var fixture = new SessionFixture();
        await fixture.WriteExpiredSessionAsync();
        var calls = 0;
        using var http = new HttpClient(new Handler(request =>
        {
            Assert.EndsWith("/token", request.RequestUri!.AbsolutePath);
            if (++calls == 1) throw new HttpRequestException("offline");
            return SessionFixture.AuthResponse();
        }));
        using var client = fixture.Client(http);

        Assert.IsAssignableFrom<HttpRequestException>(await Record.ExceptionAsync(() => client.BootstrapAsync()));
        Assert.Equal("existing-user", await client.BootstrapAsync());
        Assert.Equal(2, calls);
    }

    [Theory]
    [InlineData("refresh_token_not_found")]
    [InlineData("refresh_token_already_used")]
    [InlineData("session_not_found")]
    public async Task ExplicitRefreshRejectionRequiresRecoveryWithoutSignup(string code)
    {
        using var fixture = new SessionFixture();
        await fixture.WriteExpiredSessionAsync();
        var calls = 0;
        using var http = new HttpClient(new Handler(request =>
        {
            calls++;
            Assert.EndsWith("/token", request.RequestUri!.AbsolutePath);
            return new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent(JsonSerializer.Serialize(new { code, msg = "Session rejected" }))
            };
        }));
        using var client = fixture.Client(http);

        var error = await Assert.ThrowsAsync<SupabaseSessionExpiredException>(() => client.BootstrapAsync());

        Assert.Equal("existing-user", error.UserId);
        Assert.Equal(1, calls);
        Assert.Contains("old-refresh", await File.ReadAllTextAsync(fixture.SessionPath));
    }

    [Theory]
    [InlineData("{not-json")]
    [InlineData("null")]
    [InlineData("{}")]
    [InlineData("""{"access_token":"a","refresh_token":"r","expires_at":"2026-01-01T00:00:00Z"}""")]
    public async Task InvalidExistingSessionNeverCreatesReplacementAccount(string content)
    {
        using var fixture = new SessionFixture();
        await File.WriteAllTextAsync(fixture.SessionPath, content);
        var calls = 0;
        using var http = new HttpClient(new Handler(_ =>
        {
            calls++;
            return SessionFixture.AuthResponse();
        }));
        using var client = fixture.Client(http);

        var error = await Record.ExceptionAsync(() => client.BootstrapAsync());

        Assert.NotNull(error);
        Assert.Equal(0, calls);
        Assert.Equal(content, await File.ReadAllTextAsync(fixture.SessionPath));
        Assert.Null(client.CurrentUid);
    }

    [Fact]
    public async Task RefreshPreservesPreviousSessionInBackup()
    {
        using var fixture = new SessionFixture();
        await fixture.WriteExpiredSessionAsync();
        var original = await File.ReadAllTextAsync(fixture.SessionPath);
        using var http = new HttpClient(new Handler(_ => SessionFixture.AuthResponse()));
        using var client = fixture.Client(http);

        Assert.Equal("existing-user", await client.BootstrapAsync());

        Assert.Equal(original, await File.ReadAllTextAsync(fixture.SessionPath + ".bak"));
        var saved = JsonSerializer.Deserialize<SupabaseSession>(await File.ReadAllTextAsync(fixture.SessionPath), JsonOptions.Supabase);
        Assert.Equal("new-refresh", saved!.RefreshToken);
        Assert.Empty(Directory.GetFiles(fixture.Root, "*.tmp"));
    }

    [Fact]
    public async Task FailedSessionReplacementRetriesSavingRefreshedTokensBeforeReturningSuccess()
    {
        using var fixture = new SessionFixture();
        await fixture.WriteExpiredSessionAsync();
        var original = await File.ReadAllTextAsync(fixture.SessionPath);
        var calls = 0;
        using var http = new HttpClient(new Handler(_ =>
        {
            calls++;
            return SessionFixture.AuthResponse();
        }));
        using var client = fixture.Client(http);
        using (var lockedFile = new FileStream(fixture.SessionPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            await Assert.ThrowsAnyAsync<IOException>(() => client.BootstrapAsync());
            Assert.Equal(original, await File.ReadAllTextAsync(fixture.SessionPath));
        }

        Assert.Equal("existing-user", await client.BootstrapAsync());

        Assert.Equal(1, calls);
        Assert.Contains("new-refresh", await File.ReadAllTextAsync(fixture.SessionPath));
        Assert.Equal(original, await File.ReadAllTextAsync(fixture.SessionPath + ".bak"));
        Assert.Empty(Directory.GetFiles(fixture.Root, "*.tmp"));
    }

    [Fact]
    public async Task CanceledRefreshLeavesOriginalSessionUntouched()
    {
        using var fixture = new SessionFixture();
        await fixture.WriteExpiredSessionAsync();
        var original = await File.ReadAllTextAsync(fixture.SessionPath);
        using var cancellation = new CancellationTokenSource();
        using var http = new HttpClient(new Handler(_ =>
        {
            cancellation.Cancel();
            throw new OperationCanceledException(cancellation.Token);
        }));
        using var client = fixture.Client(http);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => client.BootstrapAsync(cancellation.Token));

        Assert.Equal(original, await File.ReadAllTextAsync(fixture.SessionPath));
        Assert.Empty(Directory.GetFiles(fixture.Root, "*.tmp"));
    }

    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(respond(request));
    }

    private sealed class SessionFixture : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "PingSessionTests", Guid.NewGuid().ToString("N"));
        public string SessionPath => Path.Combine(Root, "SupabaseSession.json");

        public SessionFixture()
        {
            Directory.CreateDirectory(Root);
            File.WriteAllText(Path.Combine(Root, "Supabase.json"), """{"url":"https://example.supabase.co","anonKey":"public-key"}""");
        }

        public SupabaseClient Client(HttpClient http) => new(http, Path.Combine(Root, "Supabase.json"), SessionPath);

        public Task WriteExpiredSessionAsync() => File.WriteAllTextAsync(SessionPath,
            JsonSerializer.Serialize(new SupabaseSession("old-access", "old-refresh", DateTimeOffset.UtcNow.AddHours(-1), "existing-user"), JsonOptions.Supabase));

        public static HttpResponseMessage AuthResponse() => new(HttpStatusCode.OK)
        {
            Content = new StringContent("""{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"user":{"id":"existing-user"}}""")
        };

        public void Dispose() => Directory.Delete(Root, recursive: true);
    }
}
