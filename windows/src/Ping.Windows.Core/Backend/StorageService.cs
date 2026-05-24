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
    private const long MaxVideoBytes = 50L * 1024 * 1024;
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
        ValidateUploadInput(localVideoPath, senderUid, videoId);
        var path = $"{senderUid}/{videoId}.mp4";
        await client.UploadObjectAsync(Bucket, path, localVideoPath, "video/mp4", cancellationToken).ConfigureAwait(false);
        return path;
    }

    public async Task<string> DownloadVideoAsync(string remotePath, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(remotePath)
            || !remotePath.EndsWith(".mp4", StringComparison.OrdinalIgnoreCase)
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

    private static void ValidateUploadInput(string localVideoPath, string senderUid, string videoId)
    {
        if (string.IsNullOrWhiteSpace(senderUid)
            || senderUid.Contains('/', StringComparison.Ordinal)
            || senderUid.Contains('\\', StringComparison.Ordinal))
        {
            throw new ArgumentException("Sender uid must be a storage-safe Supabase uid.", nameof(senderUid));
        }

        if (string.IsNullOrWhiteSpace(videoId)
            || videoId.Contains('/', StringComparison.Ordinal)
            || videoId.Contains('\\', StringComparison.Ordinal))
        {
            throw new ArgumentException("Video id must be a storage-safe object id.", nameof(videoId));
        }

        if (!string.Equals(Path.GetExtension(localVideoPath), ".mp4", StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Video upload path must point to an MP4 file.", nameof(localVideoPath));
        }

        var file = new FileInfo(localVideoPath);
        if (!file.Exists)
        {
            throw new FileNotFoundException("Video upload file does not exist.", localVideoPath);
        }

        if (file.Length <= 0)
        {
            throw new InvalidOperationException("Video upload file must be non-empty.");
        }

        if (file.Length > MaxVideoBytes)
        {
            throw new InvalidOperationException("Video upload file exceeds the 50 MB limit.");
        }
    }
}
