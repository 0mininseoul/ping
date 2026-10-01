using System.IO.Compression;
using System.Net;
using System.Text;
using Ping.Windows.Core.Updates;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class WindowsUpdateTests
{
    [Fact]
    public async Task CheckComparesNumericPackageVersionsAndNeverOffersDowngrade()
    {
        using var http = new HttpClient(new Downloads());
        var service = new WindowsUpdateService(http, (_, _) => Task.FromResult(new PackageSignature(true, "12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC", "CN=Youngmin Park")));
        Assert.Null(await service.CheckAsync(new(0, 3, 100, 0), "x64"));
        var candidate = await service.CheckAsync(new(0, 3, 9, 0), "arm64");
        Assert.Equal(new Version(0, 3, 80, 0), candidate!.Version);
        Assert.Equal("https://0minping.vercel.app/downloads/windows/Ping-Windows-v0.3.80-arm64.msix", candidate.PackageUri.AbsoluteUri);
    }

    [Theory]
    [InlineData(false, "12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC", "x64", "CN=Youngmin Park")]
    [InlineData(true, "WRONG", "x64", "CN=Youngmin Park")]
    [InlineData(true, "12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC", "arm64", "CN=Youngmin Park")]
    [InlineData(true, "12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC", "x64", "CN=Other")]
    public async Task UntrustedWrongSignerOrWrongManifestCannotBecomePreparedUpdate(bool trusted, string thumbprint, string architecture, string publisher)
    {
        var directory = Path.Combine(Path.GetTempPath(), "Ping-update-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var http = new HttpClient(new Downloads(architecture, publisher));
            var service = new WindowsUpdateService(http, (_, _) => Task.FromResult(new PackageSignature(trusted, thumbprint, "CN=Youngmin Park")));
            var candidate = await service.CheckAsync(new(0, 3, 46, 0), "x64");
            await Assert.ThrowsAnyAsync<InvalidOperationException>(() => service.PrepareAsync(candidate!, directory));
            Assert.Empty(Directory.GetFiles(directory));
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }

    [Fact]
    public async Task VerifiedUpdateContainsSelectedPackageAndMicrosoftDependency()
    {
        var directory = Path.Combine(Path.GetTempPath(), "Ping-update-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var http = new HttpClient(new Downloads());
            var service = new WindowsUpdateService(http, (path, _) => Task.FromResult(path.Contains("Runtime")
                ? new PackageSignature(true, "MICROSOFT", "CN=Microsoft Corporation, O=Microsoft Corporation")
                : new PackageSignature(true, "12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC", "CN=Youngmin Park")));
            var candidate = await service.CheckAsync(new(0, 3, 46, 0), "x64");
            var prepared = await service.PrepareAsync(candidate!, directory);
            Assert.Equal("Ping-Windows-v0.3.80-x64.msix", Path.GetFileName(prepared.PackagePath));
            Assert.Single(prepared.DependencyPaths); Assert.True(File.Exists(prepared.DependencyPaths[0]));
            Assert.Equal(new Version(0, 3, 80, 0), prepared.Version);
        }
        finally { Directory.Delete(directory, true); }
    }

    [Fact]
    public async Task DependencyTraversalCannotWriteOutsideOwnedUpdateDirectory()
    {
        var directory = Path.Combine(Path.GetTempPath(), "Ping-update-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var http = new HttpClient(new Downloads(dependency: "../outside.msix"));
            var service = new WindowsUpdateService(http, (_, _) => Task.FromResult(new PackageSignature(true, "12D9D5539B1851EE1A0725CCFCB6A9CCD098DCDC", "CN=Youngmin Park")));
            var candidate = await service.CheckAsync(new(0, 3, 46, 0), "x64");
            await Assert.ThrowsAsync<InvalidOperationException>(() => service.PrepareAsync(candidate!, directory));
            Assert.Empty(Directory.GetFiles(directory));
        }
        finally { if (Directory.Exists(directory)) Directory.Delete(directory, true); }
    }

    private sealed class Downloads(string architecture = "x64", string publisher = "CN=Youngmin Park", string dependency = "Dependencies/x64/Microsoft.WindowsAppRuntime.2.msix") : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var name = request.RequestUri!.AbsolutePath;
            byte[] data;
            if (name.EndsWith("latest-version.txt")) data = Encoding.UTF8.GetBytes("0.3.80\n");
            else if (name.EndsWith(".txt")) data = Encoding.UTF8.GetBytes(dependency);
            else if (name.Contains("Runtime")) data = [1, 2, 3];
            else
            {
                using var output = new MemoryStream();
                using (var zip = new ZipArchive(output, ZipArchiveMode.Create, true))
                {
                    using var writer = new StreamWriter(zip.CreateEntry("AppxManifest.xml").Open());
                    writer.Write($"<Package><Identity Name=\"YoungminPark.PingWindows\" Publisher=\"{publisher}\" Version=\"0.3.80.0\" ProcessorArchitecture=\"{architecture}\" /></Package>");
                }
                data = output.ToArray();
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(data) });
        }
    }
}
