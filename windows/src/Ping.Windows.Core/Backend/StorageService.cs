namespace Ping.Windows.Core.Backend;

public interface IStorageService
{
    Task<string> UploadVideoAsync(
        string localVideoPath,
        string senderUid,
        string videoId,
        IReadOnlyCollection<string> authorizedReceiverUids,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken = default);
}

public sealed class StorageService(SupabaseClient client) : IStorageService
{
    private const string Bucket = "ping-videos";

    public async Task<string> UploadVideoAsync(
        string localVideoPath,
        string senderUid,
        string videoId,
        IReadOnlyCollection<string> authorizedReceiverUids,
        DateTimeOffset expiresAt,
        CancellationToken cancellationToken = default)
    {
        _ = authorizedReceiverUids;
        _ = expiresAt;
        var path = $"{senderUid}/{videoId}.mp4";
        await client.UploadObjectAsync(Bucket, path, localVideoPath, "video/mp4", cancellationToken).ConfigureAwait(false);
        return path;
    }
}
