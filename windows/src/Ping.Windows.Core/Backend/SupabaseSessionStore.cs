using System.Text.Json;

namespace Ping.Windows.Core.Backend;

public sealed class SupabaseSessionReadException(Exception innerException)
    : IOException("기존 Ping 계정 파일을 읽을 수 없습니다. 계정 파일을 보존한 채 복구가 필요합니다.", innerException);

public sealed class SupabaseSessionStore(string path)
{
    public async Task<SupabaseSession?> LoadAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            var session = await JsonSerializer.DeserializeAsync<SupabaseSession>(stream, JsonOptions.Supabase, cancellationToken).ConfigureAwait(false);
            if (session is null || string.IsNullOrWhiteSpace(session.AccessToken) || string.IsNullOrWhiteSpace(session.RefreshToken)
                || string.IsNullOrWhiteSpace(session.UserId) || session.ExpiresAt == default)
            {
                throw new JsonException("Incomplete session.");
            }
            return session;
        }
        catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException)
        {
            return null;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            throw new SupabaseSessionReadException(ex);
        }
    }

    public async Task SaveAsync(SupabaseSession session, CancellationToken cancellationToken = default)
    {
        var fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        var temporaryPath = fullPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                4096, FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await JsonSerializer.SerializeAsync(stream, session, JsonOptions.Supabase, cancellationToken).ConfigureAwait(false);
                await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
                stream.Flush(flushToDisk: true);
            }
            cancellationToken.ThrowIfCancellationRequested();
            if (File.Exists(fullPath))
            {
                File.Replace(temporaryPath, fullPath, fullPath + ".bak");
            }
            else
            {
                File.Move(temporaryPath, fullPath);
            }
        }
        finally
        {
            if (File.Exists(temporaryPath)) File.Delete(temporaryPath);
        }
    }
}
