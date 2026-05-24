namespace Ping.Windows.Core.LocalState;

public enum LocalArchiveKind
{
    Sent,
    Received
}

public sealed record LocalArchiveEntry(
    LocalArchiveKind Kind,
    string Label,
    string FilePath,
    DateTimeOffset CreatedAt);

public sealed class LocalArchive
{
    public LocalArchive(string rootDirectory)
    {
        if (string.IsNullOrWhiteSpace(rootDirectory))
        {
            throw new ArgumentException("Archive root directory is required.", nameof(rootDirectory));
        }

        RootDirectory = Path.GetFullPath(rootDirectory);
    }

    public string RootDirectory { get; }

    public static string DefaultRootDirectory()
    {
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        if (string.IsNullOrWhiteSpace(documents))
        {
            documents = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        }

        return Path.Combine(documents, "Ping");
    }

    public async Task<LocalArchiveEntry> SaveSentCopyAsync(
        string sourceMp4Path,
        LocalArchiveKind kind,
        string label,
        DateTimeOffset? createdAt = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(sourceMp4Path))
        {
            throw new ArgumentException("Source MP4 path is required.", nameof(sourceMp4Path));
        }

        if (!File.Exists(sourceMp4Path))
        {
            throw new FileNotFoundException("Source MP4 file does not exist.", sourceMp4Path);
        }

        if (!string.Equals(Path.GetExtension(sourceMp4Path), ".mp4", StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Only MP4 files can be archived.", nameof(sourceMp4Path));
        }

        var timestamp = createdAt ?? DateTimeOffset.Now;
        var safeLabel = SanitizeLabel(label);
        var folder = FolderFor(kind);
        Directory.CreateDirectory(folder);

        var prefix = kind == LocalArchiveKind.Sent ? "to" : "from";
        var fileName = $"{timestamp:yyyy-MM-dd_HH-mm-ss}_{prefix}_{safeLabel}.mp4";
        var destination = Path.Combine(folder, fileName);

        await using var source = File.Open(sourceMp4Path, FileMode.Open, FileAccess.Read, FileShare.Read);
        await using var target = File.Open(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        await source.CopyToAsync(target, cancellationToken).ConfigureAwait(false);

        return new LocalArchiveEntry(kind, safeLabel, destination, timestamp);
    }

    public Task DeleteAsync(LocalArchiveEntry entry, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(entry);
        cancellationToken.ThrowIfCancellationRequested();

        var fullPath = Path.GetFullPath(entry.FilePath);
        if (!IsInsideRoot(fullPath))
        {
            throw new InvalidOperationException("Archive entries outside the archive root cannot be deleted.");
        }

        if (File.Exists(fullPath))
        {
            File.Delete(fullPath);
        }

        return Task.CompletedTask;
    }

    public string FolderFor(LocalArchiveKind kind)
    {
        var child = kind switch
        {
            LocalArchiveKind.Sent => "sent",
            LocalArchiveKind.Received => "received",
            _ => throw new ArgumentOutOfRangeException(nameof(kind), kind, "Unknown archive kind.")
        };

        return Path.Combine(RootDirectory, child);
    }

    public static string SanitizeLabel(string label)
    {
        var value = string.IsNullOrWhiteSpace(label) ? "unknown" : label.Trim();
        var invalid = Path.GetInvalidFileNameChars().Concat(['/', '\\', ':', '*', '?', '"', '<', '>', '|']).ToHashSet();
        var chars = value
            .Select(character => invalid.Contains(character) || char.IsControl(character) ? '_' : character)
            .ToArray();
        var sanitized = new string(chars);

        while (sanitized.Contains("__", StringComparison.Ordinal))
        {
            sanitized = sanitized.Replace("__", "_", StringComparison.Ordinal);
        }

        sanitized = sanitized.Trim(' ', '.', '_');
        return sanitized.Length == 0 ? "unknown" : sanitized;
    }

    private bool IsInsideRoot(string fullPath)
    {
        var root = RootDirectory.EndsWith(Path.DirectorySeparatorChar)
            ? RootDirectory
            : RootDirectory + Path.DirectorySeparatorChar;
        return fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase);
    }
}
