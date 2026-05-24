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
