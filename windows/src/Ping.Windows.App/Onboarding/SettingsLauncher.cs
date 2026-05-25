namespace Ping.Windows.App.Onboarding;

public static class SettingsLauncher
{
    public const string WebcamPrivacyUri = "ms-settings:privacy-webcam";
    public const string CameraSettingsUri = "ms-settings:camera";
    public const string MicrophonePrivacyUri = "ms-settings:privacy-microphone";
    public const string NotificationsPrivacyUri = "ms-settings:privacy-notifications";
    public const string GraphicsCapturePrivacyUri = "ms-settings:privacy-graphicscaptureprogrammatic";
    public const string StartupAppsUri = "ms-settings:startupapps";

    public static Task<bool> LaunchWebcamPrivacyAsync() =>
        LaunchAsync(WebcamPrivacyUri);

    public static Task<bool> LaunchMicrophonePrivacyAsync() =>
        LaunchAsync(MicrophonePrivacyUri);

    public static Task<bool> LaunchNotificationsPrivacyAsync() =>
        LaunchAsync(NotificationsPrivacyUri);

    public static Task<bool> LaunchGraphicsCapturePrivacyAsync() =>
        LaunchAsync(GraphicsCapturePrivacyUri);

    public static Task<bool> RelaunchNormallyAsync()
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        var executablePath = Environment.ProcessPath;
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            return Task.FromResult(false);
        }

        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
                "explorer.exe",
                $"\"{executablePath}\"")
            {
                UseShellExecute = false
            });
            return Task.FromResult(true);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return Task.FromResult(false);
        }
        catch (InvalidOperationException)
        {
            return Task.FromResult(false);
        }
#else
        return Task.FromResult(false);
#endif
    }

    public static async Task<bool> LaunchFolderAsync(string folderPath)
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        Directory.CreateDirectory(folderPath);
        return await global::Windows.System.Launcher.LaunchFolderPathAsync(folderPath);
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return false;
#endif
    }

    public static async Task<bool> LaunchAsync(string settingsUri)
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        return await global::Windows.System.Launcher.LaunchUriAsync(new Uri(settingsUri));
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return false;
#endif
    }
}
