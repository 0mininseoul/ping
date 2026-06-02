using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using Ping.Windows.Core.Models;

namespace Ping.Windows.Core.Backend;

public static class JsonOptions
{
    public static JsonSerializerOptions Supabase { get; } = CreateSupabaseOptions();

    private static JsonSerializerOptions CreateSupabaseOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            PropertyNamingPolicy = null
        };
        options.Converters.Add(new CaptureModeJsonConverter());
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase));
        return options;
    }
}

public interface ISupabaseRpcClient
{
    Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default);

    Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default);

    Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default);
}

public sealed class SupabaseClient : ISupabaseRpcClient, IDisposable
{
    private readonly HttpClient httpClient;
    private readonly bool ownsHttpClient;
    private readonly string configPath;
    private readonly string sessionPath;
    private readonly SemaphoreSlim authLock = new(1, 1);
    private SupabaseConfiguration? configuration;
    private SupabaseSession? session;

    public SupabaseClient(HttpClient? httpClient = null, string? configPath = null, string? sessionPath = null)
    {
        this.httpClient = httpClient ?? new HttpClient();
        ownsHttpClient = httpClient is null;
        this.configPath = configPath ?? SupabaseConfigLocator.Resolve();
        this.sessionPath = sessionPath ?? PingLocalPath("SupabaseSession.json");
    }

    public string? CurrentUid => session?.UserId;

    public async Task<string> BootstrapAsync(CancellationToken cancellationToken = default)
    {
        var authenticated = await AuthenticatedSessionAsync(cancellationToken).ConfigureAwait(false);
        return authenticated.UserId;
    }

    public async Task<IReadOnlyList<T>> RpcArrayAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
    {
        var data = await RpcDataAsync(function, body, cancellationToken).ConfigureAwait(false);
        if (data.Length == 0)
        {
            return [];
        }

        return JsonSerializer.Deserialize<IReadOnlyList<T>>(data, JsonOptions.Supabase) ?? [];
    }

    public async Task<T> RpcValueAsync<T>(string function, object? body = null, CancellationToken cancellationToken = default)
    {
        var data = await RpcDataAsync(function, body, cancellationToken).ConfigureAwait(false);
        return JsonSerializer.Deserialize<T>(data, JsonOptions.Supabase)
            ?? throw new InvalidOperationException($"RPC {function} returned an empty value.");
    }

    public async Task RpcVoidAsync(string function, object? body = null, CancellationToken cancellationToken = default)
    {
        _ = await RpcDataAsync(function, body, cancellationToken).ConfigureAwait(false);
    }

    public async Task UploadObjectAsync(
        string bucket,
        string path,
        string localPath,
        string contentType,
        CancellationToken cancellationToken = default)
    {
        var config = await LoadConfigurationAsync(cancellationToken).ConfigureAwait(false);
        var token = await AccessTokenAsync(cancellationToken).ConfigureAwait(false);
        using var request = new HttpRequestMessage(HttpMethod.Post, ObjectUrl(config.StorageUrl, bucket, path));
        request.Headers.Add("apikey", config.AnonKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Add("x-upsert", "true");
        request.Content = new ByteArrayContent(await File.ReadAllBytesAsync(localPath, cancellationToken).ConfigureAwait(false));
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(contentType);

        _ = await SendAsync(request, cancellationToken).ConfigureAwait(false);
    }

    public async Task DownloadObjectAsync(
        string bucket,
        string path,
        string localPath,
        CancellationToken cancellationToken = default)
    {
        var config = await LoadConfigurationAsync(cancellationToken).ConfigureAwait(false);
        var token = await AccessTokenAsync(cancellationToken).ConfigureAwait(false);
        using var request = new HttpRequestMessage(HttpMethod.Get, AuthenticatedObjectUrl(config.StorageUrl, bucket, path));
        request.Headers.Add("apikey", config.AnonKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var data = await SendAsync(request, cancellationToken).ConfigureAwait(false);
        var directory = Path.GetDirectoryName(localPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await File.WriteAllBytesAsync(localPath, data, cancellationToken).ConfigureAwait(false);
    }

    public async Task DeleteObjectAsync(
        string bucket,
        string path,
        CancellationToken cancellationToken = default)
    {
        var config = await LoadConfigurationAsync(cancellationToken).ConfigureAwait(false);
        var token = await AccessTokenAsync(cancellationToken).ConfigureAwait(false);
        using var request = new HttpRequestMessage(HttpMethod.Delete, ObjectUrl(config.StorageUrl, bucket, path));
        request.Headers.Add("apikey", config.AnonKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        _ = await SendAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<byte[]> RpcDataAsync(string function, object? body, CancellationToken cancellationToken)
    {
        var config = await LoadConfigurationAsync(cancellationToken).ConfigureAwait(false);
        var token = await AccessTokenAsync(cancellationToken).ConfigureAwait(false);
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri($"{config.RestUrl}/rpc/{function}"));
        request.Headers.Add("apikey", config.AnonKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Content = new ByteArrayContent(JsonSerializer.SerializeToUtf8Bytes(body ?? new { }, JsonOptions.Supabase));
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");

        return await SendAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<string> AccessTokenAsync(CancellationToken cancellationToken)
    {
        var authenticated = await AuthenticatedSessionAsync(cancellationToken).ConfigureAwait(false);
        return authenticated.AccessToken;
    }

    private async Task<SupabaseSession> AuthenticatedSessionAsync(CancellationToken cancellationToken)
    {
        if (session is { NeedsRefresh: false })
        {
            return session;
        }

        await authLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (session is { NeedsRefresh: false })
            {
                return session;
            }

            session ??= await LoadSessionAsync(cancellationToken).ConfigureAwait(false);
            SupabaseSession authenticated;
            if (session is null)
            {
                authenticated = await SignInAnonymouslyAsync(cancellationToken).ConfigureAwait(false);
            }
            else if (session.NeedsRefresh)
            {
                try
                {
                    authenticated = await RefreshSessionAsync(session.RefreshToken, cancellationToken).ConfigureAwait(false);
                }
                catch (HttpRequestException ex)
                {
                    throw new SupabaseSessionExpiredException(session.UserId, ex);
                }
            }
            else
            {
                authenticated = session;
            }

            session = authenticated;
            await SaveSessionAsync(authenticated, cancellationToken).ConfigureAwait(false);
            return authenticated;
        }
        finally
        {
            authLock.Release();
        }
    }

    private async Task<SupabaseSession?> LoadSessionAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(sessionPath))
        {
            return null;
        }

        try
        {
            await using var stream = File.OpenRead(sessionPath);
            return await JsonSerializer.DeserializeAsync<SupabaseSession>(stream, JsonOptions.Supabase, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }

    private async Task SaveSessionAsync(SupabaseSession value, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(sessionPath) ?? ".");
        await using var stream = File.Create(sessionPath);
        await JsonSerializer.SerializeAsync(stream, value, JsonOptions.Supabase, cancellationToken).ConfigureAwait(false);
    }

    private async Task<SupabaseSession> SignInAnonymouslyAsync(CancellationToken cancellationToken)
    {
        var config = await LoadConfigurationAsync(cancellationToken).ConfigureAwait(false);
        using var request = CreateAuthRequest(config, HttpMethod.Post, new Uri($"{config.AuthUrl}/signup"), new
        {
            data = new { },
            gotrue_meta_security = new { }
        });

        return await SendAuthRequestAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private async Task<SupabaseSession> RefreshSessionAsync(string refreshToken, CancellationToken cancellationToken)
    {
        var config = await LoadConfigurationAsync(cancellationToken).ConfigureAwait(false);
        using var request = CreateAuthRequest(
            config,
            HttpMethod.Post,
            new Uri($"{config.AuthUrl}/token?grant_type=refresh_token"),
            new { refresh_token = refreshToken });

        return await SendAuthRequestAsync(request, cancellationToken).ConfigureAwait(false);
    }

    private HttpRequestMessage CreateAuthRequest(SupabaseConfiguration config, HttpMethod method, Uri url, object body)
    {
        var request = new HttpRequestMessage(method, url);
        request.Headers.Add("apikey", config.AnonKey);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", config.AnonKey);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Content = new ByteArrayContent(JsonSerializer.SerializeToUtf8Bytes(body, JsonOptions.Supabase));
        request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        return request;
    }

    private async Task<SupabaseSession> SendAuthRequestAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var data = await SendAsync(request, cancellationToken).ConfigureAwait(false);
        var response = JsonSerializer.Deserialize<SupabaseAuthResponse>(data, JsonOptions.Supabase)
            ?? throw new InvalidOperationException("Supabase auth response was empty.");
        var expiresAt = response.ExpiresAt is null
            ? DateTimeOffset.UtcNow.AddSeconds(response.ExpiresIn)
            : DateTimeOffset.FromUnixTimeSeconds(response.ExpiresAt.Value);

        return new SupabaseSession(response.AccessToken, response.RefreshToken, expiresAt, response.User.Id);
    }

    private async Task<SupabaseConfiguration> LoadConfigurationAsync(CancellationToken cancellationToken)
    {
        if (configuration is not null)
        {
            return configuration;
        }

        if (!File.Exists(configPath))
        {
            throw new FileNotFoundException($"Missing Supabase runtime config: {configPath}");
        }

        await using var stream = File.OpenRead(configPath);
        var config = await JsonSerializer.DeserializeAsync<SupabaseConfiguration>(stream, JsonOptions.Supabase, cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException("Supabase runtime config was empty.");
        configuration = config.Normalize();
        return configuration;
    }

    private async Task<byte[]> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        using var response = await httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
        var data = await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
        if (!response.IsSuccessStatusCode)
        {
            throw new HttpRequestException($"Supabase request failed ({(int)response.StatusCode}): {ErrorMessage(data)}");
        }

        return data;
    }

    private static string PingLocalPath(string fileName)
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var directory = Path.Combine(localAppData, "Ping");
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, fileName);
    }

    private static Uri ObjectUrl(Uri storageUrl, string bucket, string path)
    {
        var segments = path.Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.EscapeDataString);
        return new Uri($"{storageUrl}/object/{Uri.EscapeDataString(bucket)}/{string.Join("/", segments)}");
    }

    private static Uri AuthenticatedObjectUrl(Uri storageUrl, string bucket, string path)
    {
        var segments = path.Split('/', StringSplitOptions.RemoveEmptyEntries)
            .Select(Uri.EscapeDataString);
        return new Uri($"{storageUrl}/object/authenticated/{Uri.EscapeDataString(bucket)}/{string.Join("/", segments)}");
    }

    private static string ErrorMessage(byte[] data)
    {
        if (data.Length == 0)
        {
            return "empty response body";
        }

        try
        {
            using var document = JsonDocument.Parse(data);
            foreach (var key in new[] { "message", "error_description", "error", "msg" })
            {
                if (document.RootElement.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
                {
                    return value.GetString() ?? "unknown error";
                }
            }
        }
        catch (JsonException)
        {
        }

        return System.Text.Encoding.UTF8.GetString(data);
    }

    public void Dispose()
    {
        authLock.Dispose();
        if (ownsHttpClient)
        {
            httpClient.Dispose();
        }
    }
}

public sealed record SupabaseConfiguration
{
    [JsonPropertyName("SUPABASE_URL")]
    public string? SupabaseUrl { get; init; }

    [JsonPropertyName("SUPABASE_ANON_KEY")]
    public string? SupabaseAnonKey { get; init; }

    [JsonPropertyName("supabaseUrl")]
    public string? SupabaseUrlCamel { get; init; }

    [JsonPropertyName("supabaseAnonKey")]
    public string? SupabaseAnonKeyCamel { get; init; }

    [JsonPropertyName("url")]
    public string? SupabaseUrlShort { get; init; }

    [JsonPropertyName("anonKey")]
    public string? SupabaseAnonKeyShort { get; init; }

    [JsonIgnore]
    public Uri Url { get; private init; } = null!;

    [JsonIgnore]
    public string AnonKey { get; private init; } = string.Empty;

    [JsonIgnore]
    public Uri AuthUrl => new(Url, "auth/v1");

    [JsonIgnore]
    public Uri RestUrl => new(Url, "rest/v1");

    [JsonIgnore]
    public Uri StorageUrl => new(Url, "storage/v1");

    public SupabaseConfiguration Normalize()
    {
        var urlText = SupabaseUrl ?? SupabaseUrlCamel ?? SupabaseUrlShort;
        var anonKey = SupabaseAnonKey ?? SupabaseAnonKeyCamel ?? SupabaseAnonKeyShort;
        if (!Uri.TryCreate(urlText, UriKind.Absolute, out var url) || string.IsNullOrWhiteSpace(anonKey))
        {
            throw new InvalidOperationException("Supabase.json must contain SUPABASE_URL and SUPABASE_ANON_KEY.");
        }

        return this with
        {
            Url = new Uri(url.ToString().TrimEnd('/')),
            AnonKey = anonKey
        };
    }
}

public sealed record SupabaseSession(
    [property: JsonPropertyName("access_token")] string AccessToken,
    [property: JsonPropertyName("refresh_token")] string RefreshToken,
    [property: JsonPropertyName("expires_at")] DateTimeOffset ExpiresAt,
    [property: JsonPropertyName("user_id")] string UserId)
{
    [JsonIgnore]
    public bool NeedsRefresh => ExpiresAt <= DateTimeOffset.UtcNow.AddSeconds(90);
}

internal sealed record SupabaseAuthResponse(
    [property: JsonPropertyName("access_token")] string AccessToken,
    [property: JsonPropertyName("refresh_token")] string RefreshToken,
    [property: JsonPropertyName("expires_in")] int ExpiresIn,
    [property: JsonPropertyName("expires_at")] long? ExpiresAt,
    [property: JsonPropertyName("user")] SupabaseAuthUser User);

internal sealed record SupabaseAuthUser([property: JsonPropertyName("id")] string Id);
