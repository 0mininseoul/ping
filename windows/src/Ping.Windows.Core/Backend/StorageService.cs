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

    Task DeleteVideoAsync(string remotePath, CancellationToken cancellationToken = default);
}

public interface IChatMediaStorageService
{
    Task<ChatImageUpload> UploadChatImageAsync(
        string localImagePath,
        string senderUid,
        string messageId,
        CancellationToken cancellationToken = default);

    Task<string> DownloadChatMediaAsync(
        string remotePath,
        string fileExtension,
        CancellationToken cancellationToken = default);

    Task DeleteChatMediaAsync(string remotePath, CancellationToken cancellationToken = default);
}

public sealed class StorageService(SupabaseClient client) : IStorageService, IChatMediaStorageService
{
    private const string Bucket = "ping-videos";
    private const string MediaBucket = "ping-media";
    private const long MaxVideoBytes = 50L * 1024 * 1024;
    private const long MaxImageBytes = 15L * 1024 * 1024;
    private static readonly string PlaybackCacheDirectory = Path.Combine(Path.GetTempPath(), "Ping", "playback");
    private static readonly string MediaCacheDirectory = Path.Combine(Path.GetTempPath(), "Ping", "media");

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
        ValidateVideoPath(remotePath);

        Directory.CreateDirectory(PlaybackCacheDirectory);
        var fileName = string.Join("-", remotePath.Split('/', StringSplitOptions.RemoveEmptyEntries));
        var localPath = Path.Combine(PlaybackCacheDirectory, fileName);
        if (ExistingNonEmptyFile(localPath))
        {
            return localPath;
        }

        var tempPath = $"{localPath}.{Guid.NewGuid():N}.tmp";
        try
        {
            await client.DownloadObjectAsync(Bucket, remotePath, tempPath, cancellationToken).ConfigureAwait(false);
            File.Move(tempPath, localPath, overwrite: true);
        }
        finally
        {
            TryDelete(tempPath);
        }
        return localPath;
    }

    public async Task DeleteVideoAsync(string remotePath, CancellationToken cancellationToken = default)
    {
        ValidateVideoPath(remotePath);
        await client.DeleteObjectAsync(Bucket, remotePath, cancellationToken).ConfigureAwait(false);
    }

    public async Task<ChatImageUpload> UploadChatImageAsync(
        string localImagePath,
        string senderUid,
        string messageId,
        CancellationToken cancellationToken = default)
    {
        ValidateObjectId(senderUid, nameof(senderUid), "Sender uid must be a storage-safe Supabase uid.");
        ValidateObjectId(messageId, nameof(messageId), "Message id must be a storage-safe object id.");
        var content = ValidateChatImageInput(localImagePath);
        var path = $"{senderUid}/chat-images/{messageId}.{content.FileExtension}";
        await client.UploadObjectAsync(MediaBucket, path, localImagePath, content.MimeType, cancellationToken).ConfigureAwait(false);
        return new ChatImageUpload(
            path,
            content.MimeType,
            Width: null,
            Height: null,
            FileName: Path.GetFileName(localImagePath));
    }

    public async Task<string> DownloadChatMediaAsync(
        string remotePath,
        string fileExtension,
        CancellationToken cancellationToken = default)
    {
        ValidateChatMediaPath(remotePath);
        var safeExtension = NormalizeSafeExtension(fileExtension);
        Directory.CreateDirectory(MediaCacheDirectory);
        var fileName = string.Join("-", remotePath.Split('/', StringSplitOptions.RemoveEmptyEntries));
        var localFileName = fileName.EndsWith($".{safeExtension}", StringComparison.OrdinalIgnoreCase)
            ? fileName
            : $"{fileName}.{safeExtension}";
        var localPath = Path.Combine(MediaCacheDirectory, localFileName);
        if (ExistingNonEmptyFile(localPath))
        {
            return localPath;
        }

        var tempPath = $"{localPath}.{Guid.NewGuid():N}.tmp";
        try
        {
            await client.DownloadObjectAsync(MediaBucket, remotePath, tempPath, cancellationToken).ConfigureAwait(false);
            File.Move(tempPath, localPath, overwrite: true);
        }
        finally
        {
            TryDelete(tempPath);
        }
        return localPath;
    }

    public async Task DeleteChatMediaAsync(string remotePath, CancellationToken cancellationToken = default)
    {
        ValidateChatMediaPath(remotePath);
        await client.DeleteObjectAsync(MediaBucket, remotePath, cancellationToken).ConfigureAwait(false);
    }

    private static void ValidateUploadInput(string localVideoPath, string senderUid, string videoId)
    {
        ValidateObjectId(senderUid, nameof(senderUid), "Sender uid must be a storage-safe Supabase uid.");
        ValidateObjectId(videoId, nameof(videoId), "Video id must be a storage-safe object id.");

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

    private static void ValidateVideoPath(string remotePath)
    {
        var segments = StoragePathSegments(remotePath);
        if (string.IsNullOrWhiteSpace(remotePath)
            || Path.IsPathRooted(remotePath)
            || remotePath.Contains('\\', StringComparison.Ordinal)
            || remotePath.Contains("..", StringComparison.Ordinal))
        {
            throw new ArgumentException("Video storage path must be a private ping-videos object path.", nameof(remotePath));
        }

        if (segments.Length != 2
            || string.IsNullOrWhiteSpace(segments[0])
            || string.IsNullOrWhiteSpace(segments[1])
            || !segments[1].EndsWith(".mp4", StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Video storage path must be a private ping-videos object path.", nameof(remotePath));
        }
    }

    private static void ValidateObjectId(string value, string parameterName, string message)
    {
        if (string.IsNullOrWhiteSpace(value)
            || value.Contains('/', StringComparison.Ordinal)
            || value.Contains('\\', StringComparison.Ordinal)
            || value.Contains("..", StringComparison.Ordinal))
        {
            throw new ArgumentException(message, parameterName);
        }
    }

    private static void ValidateChatMediaPath(string remotePath)
    {
        var segments = StoragePathSegments(remotePath);
        if (string.IsNullOrWhiteSpace(remotePath)
            || Path.IsPathRooted(remotePath)
            || remotePath.Contains('\\', StringComparison.Ordinal)
            || remotePath.Contains("..", StringComparison.Ordinal))
        {
            throw new ArgumentException("Chat media path must be a private ping-media chat image object path.", nameof(remotePath));
        }

        if (segments.Length != 3
            || string.IsNullOrWhiteSpace(segments[0])
            || !string.Equals(segments[1], "chat-images", StringComparison.Ordinal)
            || string.IsNullOrWhiteSpace(segments[2])
            || string.IsNullOrWhiteSpace(Path.GetExtension(segments[2])))
        {
            throw new ArgumentException("Chat media path must be a private ping-media chat image object path.", nameof(remotePath));
        }
    }

    private static string[] StoragePathSegments(string remotePath) =>
        remotePath.Split('/');

    private static (string MimeType, string FileExtension) ValidateChatImageInput(string localImagePath)
    {
        var file = new FileInfo(localImagePath);
        if (!file.Exists)
        {
            throw new FileNotFoundException("Chat image upload file does not exist.", localImagePath);
        }

        if (file.Length <= 0)
        {
            throw new InvalidOperationException("Chat image upload file must be non-empty.");
        }

        if (file.Length > MaxImageBytes)
        {
            throw new InvalidOperationException("Chat image upload file exceeds the 15 MB limit.");
        }

        var extension = NormalizeSafeExtension((Path.GetExtension(localImagePath) ?? string.Empty).TrimStart('.'));
        return extension switch
        {
            "jpg" or "jpeg" => ("image/jpeg", "jpg"),
            "png" => ("image/png", "png"),
            "heic" => ("image/heic", "heic"),
            "heif" => ("image/heif", "heif"),
            "gif" => ("image/gif", "gif"),
            "webp" => ("image/webp", "webp"),
            _ => throw new ArgumentException("Chat image must be JPEG, PNG, HEIC, HEIF, GIF, or WebP.", nameof(localImagePath))
        };
    }

    private static string NormalizeSafeExtension(string extension)
    {
        var normalized = extension.Trim().TrimStart('.').ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(normalized)
            || normalized.Contains('/', StringComparison.Ordinal)
            || normalized.Contains('\\', StringComparison.Ordinal)
            || normalized.Contains("..", StringComparison.Ordinal))
        {
            throw new ArgumentException("File extension must be storage-safe.", nameof(extension));
        }

        return normalized;
    }

    private static bool ExistingNonEmptyFile(string path)
    {
        try
        {
            var file = new FileInfo(path);
            return file.Exists && file.Length > 0;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return false;
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
        {
        }
    }
}

public sealed record ChatImageUpload(
    string Path,
    string MimeType,
    int? Width,
    int? Height,
    string? FileName);
