namespace Ping.Windows.App.Onboarding;

public static class SettingsLauncher
{
    public const string WebcamPrivacyUri = "ms-settings:privacy-webcam";
    public const string MicrophonePrivacyUri = "ms-settings:privacy-microphone";
    public const string NotificationsPrivacyUri = "ms-settings:privacy-notifications";
    public const string GraphicsCapturePrivacyUri = "ms-settings:privacy-graphicscaptureprogrammatic";

    public static Task<bool> LaunchWebcamPrivacyAsync() =>
        LaunchAsync(WebcamPrivacyUri);

    public static Task<bool> LaunchMicrophonePrivacyAsync() =>
        LaunchAsync(MicrophonePrivacyUri);

    public static Task<bool> LaunchNotificationsPrivacyAsync() =>
        LaunchAsync(NotificationsPrivacyUri);

    public static Task<bool> LaunchGraphicsCapturePrivacyAsync() =>
        LaunchAsync(GraphicsCapturePrivacyUri);

    public static async Task<bool> LaunchFolderAsync(string folderPath)
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        Directory.CreateDirectory(folderPath);
        return await Windows.System.Launcher.LaunchFolderPathAsync(folderPath);
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return false;
#endif
    }

    public static async Task<bool> LaunchAsync(string settingsUri)
    {
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        return await Windows.System.Launcher.LaunchUriAsync(new Uri(settingsUri));
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return false;
#endif
    }
}
