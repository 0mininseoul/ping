using Ping.Windows.Core.LocalState;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class LocalArchiveTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "PingLocalArchiveTests", Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task SaveSentCopyAsync_CopiesMp4IntoSentFolderWithSafeName()
    {
        var source = CreateSourceVideo("clip.mp4");
        var archive = new LocalArchive(root);
        var timestamp = new DateTimeOffset(2026, 5, 25, 14, 30, 25, TimeSpan.Zero);

        var entry = await archive.SaveSentCopyAsync(
            source,
            LocalArchiveKind.Sent,
            "Park/Youngmin:All?",
            timestamp);

        Assert.Equal(LocalArchiveKind.Sent, entry.Kind);
        Assert.Equal(timestamp, entry.CreatedAt);
        Assert.Equal("Park_Youngmin_All", entry.Label);
        Assert.Equal(Path.Combine(root, "sent", "2026-05-25_14-30-25_to_Park_Youngmin_All.mp4"), entry.FilePath);
        Assert.True(File.Exists(entry.FilePath));
        Assert.Equal(await File.ReadAllBytesAsync(source), await File.ReadAllBytesAsync(entry.FilePath));
    }

    [Fact]
    public async Task SaveSentCopyAsync_RejectsNonMp4Sources()
    {
        var source = CreateSourceVideo("clip.mov");
        var archive = new LocalArchive(root);

        var exception = await Assert.ThrowsAsync<ArgumentException>(
            () => archive.SaveSentCopyAsync(source, LocalArchiveKind.Sent, "partner"));

        Assert.Contains("MP4", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task DeleteAsync_RemovesBookkeptFile()
    {
        var source = CreateSourceVideo("clip.mp4");
        var archive = new LocalArchive(root);
        var entry = await archive.SaveSentCopyAsync(source, LocalArchiveKind.Received, "Youngmin");

        await archive.DeleteAsync(entry);

        Assert.False(File.Exists(entry.FilePath));
    }

    [Fact]
    public async Task SaveSentCopyAsync_AddsSuffixForTimestampCollisions()
    {
        var source = CreateSourceVideo("clip.mp4");
        var archive = new LocalArchive(root);
        var timestamp = new DateTimeOffset(2026, 5, 25, 14, 30, 25, TimeSpan.Zero);

        var first = await archive.SaveSentCopyAsync(source, LocalArchiveKind.Received, "Youngmin", timestamp);
        var second = await archive.SaveSentCopyAsync(source, LocalArchiveKind.Received, "Youngmin", timestamp);

        Assert.Equal(Path.Combine(root, "received", "2026-05-25_14-30-25_from_Youngmin.mp4"), first.FilePath);
        Assert.Equal(Path.Combine(root, "received", "2026-05-25_14-30-25_from_Youngmin-2.mp4"), second.FilePath);
    }

    [Fact]
    public async Task ExistingCopyPath_ReturnsExactTimestampCopy()
    {
        var source = CreateSourceVideo("clip.mp4");
        var archive = new LocalArchive(root);
        var timestamp = new DateTimeOffset(2026, 5, 25, 14, 30, 25, TimeSpan.Zero);

        var entry = await archive.SaveSentCopyAsync(source, LocalArchiveKind.Received, "Youngmin", timestamp);

        Assert.Equal(entry.FilePath, archive.ExistingCopyPath(LocalArchiveKind.Received, "Youngmin", timestamp));
        Assert.Null(archive.ExistingCopyPath(
            LocalArchiveKind.Received,
            "Youngmin",
            timestamp.AddSeconds(1)));
    }

    [Fact]
    public async Task ExistingCopyPath_DistinguishesFractionalTimestampsWithinSameSecond()
    {
        var source = CreateSourceVideo("clip.mp4");
        var archive = new LocalArchive(root);
        var firstTimestamp = new DateTimeOffset(2026, 5, 25, 14, 30, 25, 100, TimeSpan.Zero);
        var secondTimestamp = new DateTimeOffset(2026, 5, 25, 14, 30, 25, 900, TimeSpan.Zero);

        var first = await archive.SaveSentCopyAsync(source, LocalArchiveKind.Received, "Youngmin", firstTimestamp);
        var second = await archive.SaveSentCopyAsync(source, LocalArchiveKind.Received, "Youngmin", secondTimestamp);

        Assert.NotEqual(first.FilePath, second.FilePath);
        Assert.Equal(first.FilePath, archive.ExistingCopyPath(LocalArchiveKind.Received, "Youngmin", firstTimestamp));
        Assert.Equal(second.FilePath, archive.ExistingCopyPath(LocalArchiveKind.Received, "Youngmin", secondTimestamp));
    }

    [Fact]
    public void EnsureFolders_CreatesSentAndReceivedDirectories()
    {
        var archive = new LocalArchive(root);

        archive.EnsureFolders();

        Assert.True(Directory.Exists(Path.Combine(root, "sent")));
        Assert.True(Directory.Exists(Path.Combine(root, "received")));
    }

    [Fact]
    public void DeleteExpiredFiles_RemovesOnlyOldMp4Copies()
    {
        var archive = new LocalArchive(root);
        archive.EnsureFolders();
        var now = new DateTimeOffset(2026, 5, 25, 12, 0, 0, TimeSpan.Zero);
        var oldTime = now.AddDays(-31).UtcDateTime;
        var freshTime = now.AddDays(-5).UtcDateTime;
        var oldSent = Path.Combine(root, "sent", "old.mp4");
        var freshReceived = Path.Combine(root, "received", "fresh.mp4");
        var oldNote = Path.Combine(root, "sent", "old.txt");
        File.WriteAllBytes(oldSent, [0x00]);
        File.WriteAllBytes(freshReceived, [0x01]);
        File.WriteAllText(oldNote, "keep");
        File.SetLastWriteTimeUtc(oldSent, oldTime);
        File.SetLastWriteTimeUtc(freshReceived, freshTime);
        File.SetLastWriteTimeUtc(oldNote, oldTime);

        var deleted = archive.DeleteExpiredFiles(now);

        Assert.Equal(1, deleted);
        Assert.False(File.Exists(oldSent));
        Assert.True(File.Exists(freshReceived));
        Assert.True(File.Exists(oldNote));
    }

    public void Dispose()
    {
        if (Directory.Exists(root))
        {
            Directory.Delete(root, recursive: true);
        }
    }

    private string CreateSourceVideo(string fileName)
    {
        Directory.CreateDirectory(root);
        var source = Path.Combine(root, fileName);
        File.WriteAllBytes(source, [0x00, 0x01, 0x02, 0x03]);
        return source;
    }
}
