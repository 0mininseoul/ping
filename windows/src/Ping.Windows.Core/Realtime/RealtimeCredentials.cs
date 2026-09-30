namespace Ping.Windows.Core.Realtime;

public sealed class RealtimeCredentials(Uri projectUrl, string anonKey, string accessToken, string userUid)
{
    public Uri ProjectUrl { get; } = projectUrl;
    public string AnonKey { get; } = anonKey;
    public string AccessToken { get; } = accessToken;
    public string UserUid { get; } = userUid;
    public override string ToString() => "Realtime credentials";
}

public sealed class RealtimeIdentityChangedException() : Exception("Realtime account changed; previous subscriptions were stopped.");

public interface IRealtimeCredentialsProvider
{
    Task<RealtimeCredentials> GetRealtimeCredentialsAsync(CancellationToken cancellationToken = default);
}

public interface IRealtimeTransport : IAsyncDisposable
{
    Task ConnectAsync(Uri endpoint, string anonKey, string token, CancellationToken cancellationToken);
    Task SendAsync(string text, CancellationToken cancellationToken);
    Task<string?> ReceiveAsync(CancellationToken cancellationToken);
}

public sealed record RealtimeConnectionOptions(TimeSpan JoinTimeout, TimeSpan HeartbeatInterval, TimeSpan HeartbeatTimeout)
{
    public static RealtimeConnectionOptions Default { get; } = new(TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(25), TimeSpan.FromSeconds(10));
}
