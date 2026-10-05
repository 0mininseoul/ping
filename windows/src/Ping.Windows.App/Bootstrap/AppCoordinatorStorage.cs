namespace Ping.Windows.App.Bootstrap;

internal sealed record AppCoordinatorStorage(
    string QuickSendSettingsPath,
    string MirrorPlacementPath,
    string ArchiveDirectory,
    string NotificationDirectory)
{
    public static AppCoordinatorStorage InDirectory(string directory) => new(
        Path.Combine(directory, "QuickSendSettings.json"),
        Path.Combine(directory, "MirrorPlacement.json"),
        Path.Combine(directory, "archive"),
        Path.Combine(directory, "notifications"));
}
