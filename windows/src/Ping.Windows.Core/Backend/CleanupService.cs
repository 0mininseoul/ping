namespace Ping.Windows.Core.Backend;

public sealed class CleanupService(ISupabaseRpcClient client)
{
    public Task RunAsync(CancellationToken cancellationToken = default) =>
        client.RpcVoidAsync(
            "ping_cleanup_expired_data",
            cancellationToken: cancellationToken);
}
