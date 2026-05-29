namespace Ping.Windows.Core.Backend;

/// <summary>
/// Resolves which Supabase runtime config file Ping should read.
///
/// A user-writable override under <c>%LOCALAPPDATA%\Ping\Supabase.json</c> wins
/// so power users can point Ping at a different backend. Otherwise the
/// <c>Supabase.json</c> bundled inside the installed app package (next to the
/// executable) is used, so a freshly installed Ping connects to the shared
/// backend with zero manual setup.
/// </summary>
public static class SupabaseConfigLocator
{
    public const string ConfigFileName = "Supabase.json";

    /// <summary>User-writable override location under %LOCALAPPDATA%\Ping.</summary>
    public static string UserConfigPath() =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Ping",
            ConfigFileName);

    /// <summary>Config bundled alongside the installed executable (the default).</summary>
    public static string BundledConfigPath() =>
        Path.Combine(AppContext.BaseDirectory, ConfigFileName);

    /// <summary>Resolves the config path using the real filesystem.</summary>
    public static string Resolve() =>
        Resolve(UserConfigPath(), BundledConfigPath(), File.Exists);

    /// <summary>
    /// Picks the user override when present, then the bundled config. When
    /// neither exists yet, returns the user path so error messages and the
    /// onboarding "open config folder" action point at the writable location.
    /// </summary>
    public static string Resolve(string userConfigPath, string bundledConfigPath, Func<string, bool> fileExists)
    {
        ArgumentNullException.ThrowIfNull(fileExists);

        if (fileExists(userConfigPath))
        {
            return userConfigPath;
        }

        if (fileExists(bundledConfigPath))
        {
            return bundledConfigPath;
        }

        return userConfigPath;
    }
}
