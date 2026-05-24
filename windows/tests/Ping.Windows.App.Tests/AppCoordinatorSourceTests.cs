using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class AppCoordinatorSourceTests
{
    [Fact]
    public void QuickSendDisabled_UsesNormalScreenFaceMirrorPreflightPath()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Bootstrap",
            "AppCoordinator.cs"));

        Assert.Contains("if (!quickSendSettings.Preferences.IsEnabled)", source, StringComparison.Ordinal);
        Assert.Contains("await ShowScreenFaceMirrorAsync();", source, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "sendableRooms.Length > 0 && quickSendSettings.Preferences.IsEnabled",
            source,
            StringComparison.Ordinal);
    }

    private static string RepoRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "PING_PROJECT_SPECIFICATION.md")))
        {
            directory = directory.Parent;
        }

        return directory?.FullName
            ?? throw new DirectoryNotFoundException("Could not locate Ping repository root.");
    }
}
