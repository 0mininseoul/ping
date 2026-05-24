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
    private static readonly string PlaybackCacheDirectory = Path.Combine(Path.GetTempPath(), "Ping", "playback");

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

    public async Task<string> DownloadVideoAsync(string remotePath, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(remotePath)
            || Path.IsPathRooted(remotePath)
            || remotePath.Split('/', StringSplitOptions.RemoveEmptyEntries).Length < 2
            || remotePath.Contains("..", StringComparison.Ordinal))
        {
            throw new ArgumentException("Video storage path must be a private ping-videos object path.", nameof(remotePath));
        }

        Directory.CreateDirectory(PlaybackCacheDirectory);
        var fileName = string.Join("-", remotePath.Split('/', StringSplitOptions.RemoveEmptyEntries));
        var localPath = Path.Combine(PlaybackCacheDirectory, fileName);
        await client.DownloadObjectAsync(Bucket, remotePath, localPath, cancellationToken).ConfigureAwait(false);
        return localPath;
    }
}
