using System.Diagnostics;

namespace Ping.Windows.App.Setup;

internal static class WindowsPowerShellEnvironment
{
    internal static void Normalize(ProcessStartInfo start)
    {
        // A launcher started by PowerShell7 inherits modules that Windows PowerShell cannot load.
        start.Environment.Remove("PSModulePath");
    }
}
