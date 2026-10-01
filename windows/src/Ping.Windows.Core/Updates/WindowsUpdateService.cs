using System.IO.Compression;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace Ping.Windows.Core.Updates;

public sealed record PackageSignature(bool IsTrusted, string Thumbprint, string Subject);
public sealed record WindowsUpdateCandidate(Version Version, string Architecture, Uri PackageUri);
public sealed record PreparedWindowsUpdate(Version Version, string PackagePath, IReadOnlyList<string> DependencyPaths);
public sealed record UpdateDownloadProgress(string FileName, long Bytes, long? TotalBytes);

public sealed class WindowsUpdateService(HttpClient http,
    Func<string, CancellationToken, Task<PackageSignature>> verifySignature)
{
    public const string BaseUrl = "https://0minping.vercel.app/downloads/windows/";
    public const string PackageName = "YoungminPark.PingWindows";
    public const string Publisher = "CN=Youngmin Park";
    public const string SignerThumbprint = "12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC";
    private const long MaximumPackageBytes = 512L * 1024 * 1024;

    public async Task<WindowsUpdateCandidate?> CheckAsync(Version currentVersion, string architecture, CancellationToken token = default)
    {
        ValidateArchitecture(architecture);
        var text = (await http.GetStringAsync(new Uri(BaseUrl + "latest-version.txt"), token).ConfigureAwait(false)).Trim();
        if (!Regex.IsMatch(text, @"^\d+\.\d+\.\d+$") || !Version.TryParse(text, out var parsed)
            || parsed.Major > ushort.MaxValue || parsed.Minor > ushort.MaxValue || parsed.Build > ushort.MaxValue)
            throw new InvalidOperationException("Invalid Windows release version.");
        var version = new Version(parsed.Major, parsed.Minor, parsed.Build, 0);
        return version > currentVersion ? new(version, architecture, PackageUri(version, architecture)) : null;
    }

    public async Task<PreparedWindowsUpdate> PrepareAsync(WindowsUpdateCandidate candidate, string directory,
        IProgress<UpdateDownloadProgress>? progress = null, CancellationToken token = default)
    {
        ValidateArchitecture(candidate.Architecture);
        if (candidate.Version.Revision != 0 || candidate.PackageUri != PackageUri(candidate.Version, candidate.Architecture))
            throw new InvalidOperationException("Unexpected update package location.");
        Directory.CreateDirectory(directory);
        var created = new List<string>();
        try
        {
            var index = await http.GetStringAsync(new Uri(BaseUrl + $"dependencies-{candidate.Architecture}.txt"), token).ConfigureAwait(false);
            var relativeDependencies = index.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            if (relativeDependencies.Length == 0 || relativeDependencies.Length > 16 || relativeDependencies.Any(path =>
                !Regex.IsMatch(path, $@"^Dependencies/{candidate.Architecture}/[a-zA-Z0-9_.-]+\.(msix|appx)$") || path.Contains("..", StringComparison.Ordinal)))
                throw new InvalidOperationException("Invalid update dependency manifest.");
            var packagePath = Path.Combine(directory, Path.GetFileName(candidate.PackageUri.AbsolutePath));
            await DownloadAsync(candidate.PackageUri, packagePath, created, progress, token).ConfigureAwait(false);
            ValidateIdentity(packagePath, candidate);
            var signature = await verifySignature(packagePath, token).ConfigureAwait(false);
            if (!signature.IsTrusted || !string.Equals(signature.Thumbprint, SignerThumbprint, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Windows update signer could not be verified.");
            var dependencies = new List<string>();
            foreach (var relative in relativeDependencies)
            {
                var path = Path.Combine(directory, Path.GetFileName(relative));
                await DownloadAsync(new Uri(BaseUrl + relative), path, created, progress, token).ConfigureAwait(false);
                var dependencySignature = await verifySignature(path, token).ConfigureAwait(false);
                if (!dependencySignature.IsTrusted || !dependencySignature.Subject.Contains("O=Microsoft Corporation", StringComparison.Ordinal))
                    throw new InvalidOperationException("Windows update dependency signer could not be verified.");
                dependencies.Add(path);
            }
            token.ThrowIfCancellationRequested();
            return new(candidate.Version, packagePath, dependencies);
        }
        catch
        {
            foreach (var path in created) File.Delete(path);
            throw;
        }
    }

    private async Task DownloadAsync(Uri uri, string path, List<string> created, IProgress<UpdateDownloadProgress>? progress, CancellationToken token)
    {
        using var response = await http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength;
        if (total > MaximumPackageBytes) throw new InvalidOperationException("Update package is too large.");
        await using var input = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
        await using var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous);
        created.Add(path);
        var buffer = new byte[65536]; long bytes = 0;
        for (var count = await input.ReadAsync(buffer, token).ConfigureAwait(false); count > 0; count = await input.ReadAsync(buffer, token).ConfigureAwait(false))
        {
            bytes += count;
            if (bytes > MaximumPackageBytes) throw new InvalidOperationException("Update package is too large.");
            await output.WriteAsync(buffer.AsMemory(0, count), token).ConfigureAwait(false);
            progress?.Report(new(Path.GetFileName(path), bytes, total));
        }
        if (total is not null && bytes != total) throw new IOException("Update download was incomplete.");
        await output.FlushAsync(token).ConfigureAwait(false);
    }

    public static void ValidateIdentity(string packagePath, WindowsUpdateCandidate candidate)
    {
        using var zip = ZipFile.OpenRead(packagePath);
        var entry = zip.GetEntry("AppxManifest.xml") ?? throw new InvalidOperationException("Update package manifest missing.");
        if (entry.Length > 131072) throw new InvalidOperationException("Update package manifest is too large.");
        using var stream = entry.Open();
        var identity = XDocument.Load(stream).Root?.Elements().SingleOrDefault(element => element.Name.LocalName == "Identity");
        if (identity?.Attribute("Name")?.Value != PackageName || identity.Attribute("Publisher")?.Value != Publisher
            || identity.Attribute("Version")?.Value != candidate.Version.ToString(4)
            || identity.Attribute("ProcessorArchitecture")?.Value != candidate.Architecture)
            throw new InvalidOperationException("Update package identity does not match Ping.");
    }

    private static Uri PackageUri(Version version, string architecture) => new(BaseUrl + $"Ping-Windows-v{version.ToString(3)}-{architecture}.msix");
    private static void ValidateArchitecture(string architecture)
    {
        if (architecture is not ("x64" or "arm64")) throw new ArgumentException("Unsupported Windows package architecture.", nameof(architecture));
    }
}
