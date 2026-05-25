namespace Ping.Windows.App.Onboarding;

public enum WindowsSupportStatus
{
    Supported,
    UnsupportedWindows10,
    UnsupportedOldWindows11
}

public static class WindowsVersionProbe
{
    public const int Windows11FirstBuild = 22000;
    public const int Windows1124H2Build = 26100;

    public static WindowsSupportStatus CurrentStatus() =>
        StatusFor(Environment.OSVersion.Version);

    public static WindowsSupportStatus StatusFor(Version version)
    {
        if (version.Major < 10 || version.Build < Windows11FirstBuild)
        {
            return WindowsSupportStatus.UnsupportedWindows10;
        }

        if (version.Build < Windows1124H2Build)
        {
            return WindowsSupportStatus.UnsupportedOldWindows11;
        }

        return WindowsSupportStatus.Supported;
    }
}
