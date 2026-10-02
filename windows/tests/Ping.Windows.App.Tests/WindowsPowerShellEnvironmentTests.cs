using System.Diagnostics;
using Ping.Windows.App.Setup;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class WindowsPowerShellEnvironmentTests
{
    [Fact]
    public async Task IntermediateLauncherLoadsWindowsSignatureModuleDespiteIncompatibleParentModule()
    {
        if (!OperatingSystem.IsWindows()) return;
        var root = Path.Combine(Path.GetTempPath(), "Ping-ps-environment-" + Guid.NewGuid().ToString("N"));
        var module = Path.Combine(root, "Microsoft.PowerShell.Security");
        Directory.CreateDirectory(module);
        try
        {
            await File.WriteAllTextAsync(Path.Combine(module, "Microsoft.PowerShell.Security.psd1"),
                "@{ ModuleVersion='99.0'; RootModule='incompatible.psm1'; FunctionsToExport=@('Get-AuthenticodeSignature') }");
            await File.WriteAllTextAsync(Path.Combine(module, "incompatible.psm1"), "throw 'Incompatible parent PowerShell module'");
            var executable = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
            start.Environment["PSModulePath"] = root;
            foreach (var arg in new[] { "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference='Stop'; (Get-Command Get-AuthenticodeSignature).Module.Path" }) start.ArgumentList.Add(arg);
            WindowsPowerShellEnvironment.Normalize(start);
            using var process = Process.Start(start)!;
            var output = process.StandardOutput.ReadToEndAsync();
            var errors = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(20));
            var detail = await errors;
            Assert.True(process.ExitCode == 0, detail);
            Assert.StartsWith(Path.GetDirectoryName(executable)!, (await output).Trim(), StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            if (!Path.GetFullPath(root).StartsWith(Path.Combine(Path.GetTempPath(), "Ping-ps-environment-"), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Fixture cleanup escaped its named temporary root.");
            Directory.Delete(root, true);
        }
    }
}
