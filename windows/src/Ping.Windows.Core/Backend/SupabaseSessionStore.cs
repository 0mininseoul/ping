using System.Text.Json;

namespace Ping.Windows.Core.Backend;

public sealed class SupabaseSessionReadException(Exception innerException)
    : IOException("기존 Ping 계정 파일을 읽을 수 없습니다. 계정 파일을 보존한 채 복구가 필요합니다.", innerException);

public sealed class SupabaseSessionStore(string path)
{
    public async Task<SupabaseSession?> LoadAsync(CancellationToken cancellationToken = default)
        => (await LoadAccountsAsync(cancellationToken).ConfigureAwait(false)).ActiveSession;

    internal async Task<SupabaseAccountsState> LoadAccountsAsync(CancellationToken cancellationToken)
    {
        try
        {
            await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) throw new JsonException("Incomplete session.");
            if (root.TryGetProperty("accounts", out var catalog))
            {
                var accounts = catalog.Deserialize<SavedSupabaseAccount[]>(JsonOptions.Supabase) ?? throw new JsonException("Incomplete accounts.");
                if (accounts.Any(row => row is null || !Valid(row.Session) || row.Nickname is null || row.AddedAt == default)
                    || accounts.Select(row => row.Session.UserId).Distinct(StringComparer.Ordinal).Count() != accounts.Length)
                    throw new JsonException("Invalid account catalog.");
                var uid = root.TryGetProperty("user_id", out var value) ? value.GetString() : null;
                if (accounts.Length == 0)
                {
                    if (uid is not null) throw new JsonException("Active account missing.");
                    return new([], null);
                }
                var state = new SupabaseAccountsState(accounts, uid);
                if (state.ActiveSession is null || state.ActiveSession != root.Deserialize<SupabaseSession>(JsonOptions.Supabase))
                    throw new JsonException("Active account mismatch.");
                return state;
            }
            var legacy = root.Deserialize<SupabaseSession>(JsonOptions.Supabase);
            if (!Valid(legacy)) throw new JsonException("Incomplete session.");
            return new SupabaseAccountsState([], null).Upsert(legacy!, activate: true);
        }
        catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException)
        {
            return new([], null, Initialized: false);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException)
        {
            throw new SupabaseSessionReadException(ex);
        }
    }

    public async Task SaveAsync(SupabaseSession session, CancellationToken cancellationToken = default)
        => await SaveDocumentAsync(session, cancellationToken).ConfigureAwait(false);

    internal Task SaveAccountsAsync(SupabaseAccountsState state, CancellationToken cancellationToken)
    {
        var active = state.ActiveSession;
        return SaveDocumentAsync(new
        {
            access_token = active?.AccessToken, refresh_token = active?.RefreshToken,
            expires_at = active?.ExpiresAt, user_id = active?.UserId, accounts = state.Accounts
        }, cancellationToken);
    }
    private static bool Valid(SupabaseSession? session) => session is not null
        && !string.IsNullOrWhiteSpace(session.AccessToken) && !string.IsNullOrWhiteSpace(session.RefreshToken)
        && !string.IsNullOrWhiteSpace(session.UserId) && session.ExpiresAt != default;

    private async Task SaveDocumentAsync<T>(T data, CancellationToken cancellationToken)
    {
        var fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        var temporaryPath = fullPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await using (var stream = new FileStream(temporaryPath, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                4096, FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await JsonSerializer.SerializeAsync(stream, data, JsonOptions.Supabase, cancellationToken).ConfigureAwait(false);
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
