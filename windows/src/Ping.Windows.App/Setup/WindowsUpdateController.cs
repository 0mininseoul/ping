using System.Diagnostics;
using System.Text.Json;
using Ping.Windows.Core.Updates;
using Windows.ApplicationModel;

namespace Ping.Windows.App.Setup;

internal static class WindowsUpdateController
{
    private static string PowerShellPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
    private static string HelperPath(string name) => Path.Combine(AppContext.BaseDirectory, "Assets", "Updates", name);

    internal static UpdateSettingsViewModel CreateViewModel()
    {
        try
        {
            var id = Package.Current.Id;
            if (id.Name != WindowsUpdateService.PackageName) throw new InvalidOperationException();
            var version = new Version(id.Version.Major, id.Version.Minor, id.Version.Build, id.Version.Revision);
            var architecture = id.Architecture.ToString().ToLowerInvariant();
            var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
            var service = new WindowsUpdateService(http, VerifySignatureAsync);
            return new(version.ToString(4), token => service.CheckAsync(version, architecture, token), async (candidate, progress, token) =>
            {
                var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Ping", "Updates", Guid.NewGuid().ToString("N"));
                var prepared = await service.PrepareAsync(candidate, directory, progress, token);
                token.ThrowIfCancellationRequested();
                await ((App)Microsoft.UI.Xaml.Application.Current).ApplyPreparedUpdateAsync(prepared);
            }, http.Dispose);
        }
        catch (InvalidOperationException)
        {
            return new("로컬 개발 빌드", _ => throw new InvalidOperationException("Install the packaged version to update."), (_, _, _) => Task.CompletedTask);
        }
    }

    internal static async Task<PackageSignature> VerifySignatureAsync(string path, CancellationToken token)
    {
        var start = ScriptStartInfo(HelperPath("Verify-Package.ps1"));
        start.RedirectStandardOutput = true; start.RedirectStandardError = true;
        start.ArgumentList.Add("-PackagePath"); start.ArgumentList.Add(path);
        using var process = Process.Start(start) ?? throw new IOException("Windows signature verification could not start.");
        try
        {
            var output = process.StandardOutput.ReadToEndAsync(token);
            var errors = process.StandardError.ReadToEndAsync(token);
            await process.WaitForExitAsync(token);
            await errors;
            if (process.ExitCode != 0) throw new InvalidOperationException("Windows signature verification failed.");
            return JsonSerializer.Deserialize<PackageSignature>(await output) ?? throw new InvalidOperationException("Signature result missing.");
        }
        catch { if (!process.HasExited) process.Kill(entireProcessTree: true); throw; }
    }

    internal static void StartInstaller(PreparedWindowsUpdate update)
    {
        var directory = Path.GetDirectoryName(update.PackagePath)!;
        var script = Path.Combine(directory, "Apply-Update.ps1");
        File.Copy(HelperPath("Apply-Update.ps1"), script, overwrite: false);
        var dependencies = Path.Combine(directory, "dependencies.json");
        File.WriteAllText(dependencies, JsonSerializer.Serialize(update.DependencyPaths));
        var start = ScriptStartInfo(script);
        foreach (var (name, value) in new[] { ("-PackagePath", update.PackagePath), ("-DependencyListPath", dependencies),
            ("-ExpectedVersion", update.Version.ToString(4)), ("-ExpectedThumbprint", WindowsUpdateService.SignerThumbprint), ("-WaitForPid", Environment.ProcessId.ToString()) })
        { start.ArgumentList.Add(name); start.ArgumentList.Add(value); }
        using var process = Process.Start(start) ?? throw new IOException("Windows updater could not start.");
    }
    private static ProcessStartInfo ScriptStartInfo(string path)
    {
        var start = new ProcessStartInfo(PowerShellPath) { UseShellExecute = false, CreateNoWindow = true };
        foreach (var value in new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", path }) start.ArgumentList.Add(value);
        return start;
    }
}
