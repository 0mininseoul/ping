using System.Net;
using System.Text.Json;
using Ping.Windows.Core.Backend;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class SavedAccountTests
{
    [Fact]
    public async Task LegacySessionMigratesAndBothAccountsSurviveSwitchAndRestart()
    {
        using var files = new Files();
        await files.WriteLegacyAsync();
        using var http = new HttpClient(new Auth());
        using (var client = files.Client(http))
        {
            Assert.Equal("first", await client.BootstrapAsync());
            await client.UpdateAccountNicknameAsync("원래 계정");
            Assert.Equal("second", await client.CreateAccountAsync());
            var accounts = await client.GetAccountsAsync();
            Assert.Equal(2, accounts.Count);
            Assert.Contains(accounts, row => row.UserId == "first" && row.Nickname == "원래 계정" && !row.IsActive);
            await client.SwitchAccountAsync("first");
            Assert.Equal("first-access", (await client.GetRealtimeCredentialsAsync()).AccessToken);
        }
        using var restarted = files.Client(http);
        Assert.Equal("first", await restarted.BootstrapAsync());
        await restarted.SwitchAccountAsync("second");
        Assert.Equal("second-access", (await restarted.GetRealtimeCredentialsAsync()).AccessToken);
        Assert.Equal(2, (await restarted.GetAccountsAsync()).Count);
    }
    [Fact]
    public async Task RemovingFinalAccountRequiresExplicitCreationInsteadOfAutomaticSignup()
    {
        using var files = new Files(); await files.WriteLegacyAsync();
        var handler = new Auth(); using var http = new HttpClient(handler); using var client = files.Client(http);
        await client.RemoveAccountAsync("first");
        Assert.Empty(await client.GetAccountsAsync());
        Assert.Null(client.CurrentUid);
        await Assert.ThrowsAsync<SupabaseAccountRequiredException>(() => client.BootstrapAsync());
        Assert.Equal(0, handler.Calls);
        Assert.Equal("second", await client.CreateAccountAsync());
        Assert.Equal(1, handler.Calls);
    }
    [Fact]
    public async Task FailedSwitchPreservesDurableAndRunningIdentity()
    {
        using var files = new Files(); await files.WriteLegacyAsync();
        using var http = new HttpClient(new Auth()); using var client = files.Client(http);
        await client.CreateAccountAsync();
        var before = await File.ReadAllTextAsync(files.SessionPath);
        using (var locked = new FileStream(files.SessionPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            await Assert.ThrowsAnyAsync<IOException>(() => client.SwitchAccountAsync("first"));
            Assert.Equal("second", client.CurrentUid);
            Assert.Equal(before, await File.ReadAllTextAsync(files.SessionPath));
        }
        await client.SwitchAccountAsync("first");
        Assert.Equal("first", client.CurrentUid);
    }
    [Fact]
    public async Task BrokenCatalogCannotBeOverwrittenByExplicitSignup()
    {
        using var files = new Files();
        const string broken = """{"accounts":null,"user_id":"first"}""";
        await File.WriteAllTextAsync(files.SessionPath, broken);
        var handler = new Auth(); using var http = new HttpClient(handler); using var client = files.Client(http);
        await Assert.ThrowsAsync<SupabaseSessionReadException>(() => client.CreateAccountAsync());
        Assert.Equal(0, handler.Calls);
        Assert.Equal(broken, await File.ReadAllTextAsync(files.SessionPath));
    }
    [Fact]
    public async Task FailedCreationSaveRetriesSameCreatedAccountWithoutAnotherSignup()
    {
        using var files = new Files(); await files.WriteLegacyAsync();
        var handler = new Auth(); using var http = new HttpClient(handler); using var client = files.Client(http);
        await client.GetAccountsAsync();
        var before = await File.ReadAllTextAsync(files.SessionPath);
        using (var locked = new FileStream(files.SessionPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            await Assert.ThrowsAnyAsync<IOException>(() => client.CreateAccountAsync());
            Assert.Equal("first", client.CurrentUid);
            Assert.Equal(before, await File.ReadAllTextAsync(files.SessionPath));
        }
        Assert.Equal("second", await client.CreateAccountAsync());
        Assert.Equal(1, handler.Calls);
        Assert.Equal(2, (await client.GetAccountsAsync()).Count);
    }
    [Fact]
    public async Task RefreshUpdatesOnlyActiveAccountAndRemovingItSelectsRemainingAccount()
    {
        using var files = new Files();
        await new SupabaseSessionStore(files.SessionPath).SaveAsync(new("first-access", "first-refresh", DateTimeOffset.UtcNow.AddHours(-1), "first"));
        using var http = new HttpClient(new RefreshAuth()); using var client = files.Client(http);
        await client.CreateAccountAsync();
        await client.SwitchAccountAsync("first");
        Assert.Equal("first-refreshed", (await client.GetRealtimeCredentialsAsync()).AccessToken);
        await client.RemoveAccountAsync("first");
        Assert.Equal("second-access", (await client.GetRealtimeCredentialsAsync()).AccessToken);
        Assert.Single(await client.GetAccountsAsync());
    }
    private sealed class RefreshAuth : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var refreshing = request.RequestUri!.AbsolutePath.EndsWith("/token", StringComparison.Ordinal);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new
            {
                access_token = refreshing ? "first-refreshed" : "second-access", refresh_token = refreshing ? "first-new-refresh" : "second-refresh",
                expires_in = 3600, user = new { id = refreshing ? "first" : "second" }
            })) });
        }
    }
    [Fact]
    public async Task RefreshCannotSilentlyReplaceActiveIdentity()
    {
        using var files = new Files();
        await new SupabaseSessionStore(files.SessionPath).SaveAsync(new("first-access", "first-refresh", DateTimeOffset.UtcNow.AddHours(-1), "first"));
        var before = await File.ReadAllTextAsync(files.SessionPath);
        using var http = new HttpClient(new Auth(allowRefresh: true)); using var client = files.Client(http);
        await Assert.ThrowsAsync<SupabaseSessionExpiredException>(() => client.BootstrapAsync());
        Assert.Equal("first", client.CurrentUid);
        Assert.Equal(before, await File.ReadAllTextAsync(files.SessionPath));
    }
    private sealed class Auth(bool allowRefresh = false) : HttpMessageHandler
    {
        public int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; Assert.EndsWith(allowRefresh ? "/token" : "/signup", request.RequestUri!.AbsolutePath);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(
                """{"access_token":"second-access","refresh_token":"second-refresh","expires_in":3600,"user":{"id":"second"}}""") });
        }
    }
    private sealed class Files : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "PingSavedAccountTests", Guid.NewGuid().ToString("N"));
        public string SessionPath => Path.Combine(Root, "session.json");
        public Files()
        {
            Directory.CreateDirectory(Root);
            File.WriteAllText(Path.Combine(Root, "config.json"), """{"url":"https://example.supabase.co","anonKey":"fixture-public"}""");
        }
        public Task WriteLegacyAsync() => new SupabaseSessionStore(SessionPath).SaveAsync(new("first-access", "first-refresh",
            DateTimeOffset.UtcNow.AddHours(1), "first"));
        public SupabaseClient Client(HttpClient http) => new(http, Path.Combine(Root, "config.json"), SessionPath);
        public void Dispose() => Directory.Delete(Root, true);
    }
}
