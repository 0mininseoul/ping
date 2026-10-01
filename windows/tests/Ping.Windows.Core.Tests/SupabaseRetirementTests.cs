using System.Net;
using Ping.Windows.Core.Backend;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class SupabaseRetirementTests
{
    [Fact]
    public async Task RetirementCancelsOldHttpAndPreventsLaterWorkFromUsingAnyAccount()
    {
        var directory = Path.Combine(Path.GetTempPath(), "Ping-retirement-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            var config = Path.Combine(directory, "config.json"); var path = Path.Combine(directory, "session.json");
            await File.WriteAllTextAsync(config, """{"SUPABASE_URL":"https://fixture.invalid","SUPABASE_ANON_KEY":"public-fixture"}""");
            await new SupabaseSessionStore(path).SaveAsync(new("old-access", "old-refresh", DateTimeOffset.UtcNow.AddHours(1), "old"));
            using var handler = new HeldRequest(); using var http = new HttpClient(handler);
            using var client = new SupabaseClient(http, config, path);
            var pending = client.RpcVoidAsync("fixture"); await handler.Started.Task;
            await client.RetireAsync();
            await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
            await Assert.ThrowsAsync<ObjectDisposedException>(() => client.BootstrapAsync());
            await Assert.ThrowsAsync<ObjectDisposedException>(() => client.RpcVoidAsync("fixture"));
            await Assert.ThrowsAsync<ObjectDisposedException>(() => client.CreateAccountAsync());
            Assert.Equal("old", (await new SupabaseSessionStore(path).LoadAsync())!.UserId);
            Assert.Equal(1, handler.Calls);
        }
        finally { Directory.Delete(directory, true); }
    }

    private sealed class HeldRequest : HttpMessageHandler
    {
        public TaskCompletionSource Started { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int Calls;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++; Assert.Equal("old-access", request.Headers.Authorization!.Parameter); Started.SetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return new(HttpStatusCode.OK) { Content = new StringContent("[]") };
        }
    }
}
