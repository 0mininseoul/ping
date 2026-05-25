using System.Xml.Linq;
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

    [Fact]
    public void SenderFlowsUseSavedProfileNickname()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Bootstrap",
            "AppCoordinator.cs"));

        Assert.Contains("private string currentNickname = Environment.UserName;", source, StringComparison.Ordinal);
        Assert.Contains("userService.UpsertAsync(nickname, cancellationToken)", source, StringComparison.Ordinal);
        Assert.DoesNotContain("SenderNickname: Environment.UserName", source, StringComparison.Ordinal);
        Assert.Contains("SenderNickname: CurrentNickname", source, StringComparison.Ordinal);
        Assert.DoesNotContain("invitationService,\n            Environment.UserName", source, StringComparison.Ordinal);
    }

    [Fact]
    public void ChatNotificationActivationFocusesChatId()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Bootstrap",
            "AppCoordinator.cs"));

        Assert.DoesNotContain("_ = chatId;", source, StringComparison.Ordinal);
        Assert.Contains("OpenHistoryWindow(roomId, chatId)", source, StringComparison.Ordinal);
    }

    [Fact]
    public void HistoryComposerSupportsEnterSendAndShiftEnterNewline()
    {
        var root = RepoRoot();
        var xaml = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "History",
            "HistoryWindow.xaml"));
        var code = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "History",
            "HistoryWindow.xaml.cs"));

        Assert.Contains("x:Name=\"ChatBox\"", xaml, StringComparison.Ordinal);
        Assert.Contains("AcceptsReturn=\"True\"", xaml, StringComparison.Ordinal);
        Assert.Contains("KeyDown=\"ChatBox_KeyDown\"", xaml, StringComparison.Ordinal);
        Assert.Contains("SendChatFromComposerAsync", code, StringComparison.Ordinal);
        Assert.Contains("IsShiftDown()", code, StringComparison.Ordinal);
        Assert.Contains("args.Handled = true;", code, StringComparison.Ordinal);
    }

    [Fact]
    public void MirrorWindowsSubscribeClosedCleanupHandlers()
    {
        var root = RepoRoot();
        var face = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Capture",
            "FaceMirrorViewModel.cs"));
        var screenFace = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Capture",
            "ScreenFaceMirrorViewModel.cs"));

        Assert.Contains("Closed += HandleClosed;", face, StringComparison.Ordinal);
        Assert.Contains("viewModel.HandleWindowClosed();", face, StringComparison.Ordinal);
        Assert.Contains("Closed += HandleClosed;", screenFace, StringComparison.Ordinal);
        Assert.Contains("viewModel.HandleWindowClosed();", screenFace, StringComparison.Ordinal);
    }

    [Fact]
    public void QuickSendHudClosesAndCancelsBeforeUpload()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Capture",
            "QuickSendController.cs"));

        Assert.Contains("Closed += HandleClosed;", source, StringComparison.Ordinal);
        Assert.Contains("private void HandleClosed(object sender, WindowEventArgs args)", source, StringComparison.Ordinal);
        Assert.Contains("CancelIfBeforeUpload();", source, StringComparison.Ordinal);
        Assert.Contains("public void Hide() => CloseSafely();", source, StringComparison.Ordinal);
        Assert.Contains("if (uploadStarted || viewModel.CanRetry)", source, StringComparison.Ordinal);
    }

    [Fact]
    public void PlaybackWindowSubscribesClosedCleanupHandler()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Playback",
            "PlaybackViewModel.cs"));

        Assert.Contains("Closed += HandleClosed;", source, StringComparison.Ordinal);
        Assert.Contains("playerHost.Dispose();", source, StringComparison.Ordinal);
        Assert.Contains("CancelPausedCloseTimeout();", source, StringComparison.Ordinal);
    }

    [Fact]
    public void MirrorReviewPlaybackRemainsVisibleDuringFailedUpload()
    {
        var root = RepoRoot();
        var face = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Capture",
            "FaceMirrorViewModel.cs"));
        var screenFace = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Capture",
            "ScreenFaceMirrorViewModel.cs"));

        Assert.Contains("viewModel.State is not (MirrorState.Reviewing or MirrorState.Failed)", face, StringComparison.Ordinal);
        Assert.Contains("viewModel.State is not (MirrorState.Reviewing or MirrorState.Failed)", screenFace, StringComparison.Ordinal);
    }

    [Fact]
    public void QuickScreenFaceHotkeyCancelsActiveQuickSendWithoutStartingOverlap()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Bootstrap",
            "AppCoordinator.cs"));

        Assert.Contains("if (quickSendCancellation is not null)", source, StringComparison.Ordinal);
        Assert.Contains("quickSendCancellation.Cancel();", source, StringComparison.Ordinal);
        Assert.Contains("var cancellation = new CancellationTokenSource();", source, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "quickSendCancellation?.Cancel();\n        var cancellation = new CancellationTokenSource();",
            source,
            StringComparison.Ordinal);
    }

    [Fact]
    public void AppStartupTreatsTrayRegistrationFailureAsNonFatal()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Bootstrap",
            "AppCoordinator.cs"));

        Assert.Contains("TryAddOrUpdateTrayIcon()", source, StringComparison.Ordinal);
        Assert.Contains("catch (Win32Exception)", source, StringComparison.Ordinal);
        Assert.DoesNotContain("tray.AddOrUpdateIcon();\n        notificationController.Start();", source, StringComparison.Ordinal);
    }

    [Fact]
    public void TrayTaskbarRecreationTreatsIconFailureAsNonFatal()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Tray",
            "TrayIconController.cs"));

        Assert.Contains("TryAddOrUpdateIcon()", source, StringComparison.Ordinal);
        Assert.Contains("catch (Win32Exception)", source, StringComparison.Ordinal);
        Assert.DoesNotContain("iconVisible = false;\n            AddOrUpdateIcon();", source, StringComparison.Ordinal);
    }

    [Fact]
    public void WinUiAppUsesSingleInstanceActivationRedirection()
    {
        var root = RepoRoot();
        var project = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Ping.Windows.App.csproj"));
        var program = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Program.cs"));
        var app = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "App.xaml.cs"));
        var coordinator = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Bootstrap",
            "AppCoordinator.cs"));

        Assert.Contains("DISABLE_XAML_GENERATED_MAIN", project, StringComparison.Ordinal);
        Assert.Contains("FindOrRegisterForKey(\"Ping.Windows.App\")", program, StringComparison.Ordinal);
        Assert.Contains("RedirectActivationToAsync(args)", program, StringComparison.Ordinal);
        Assert.Contains("finally\n            {\n                SetEvent(redirectEventHandle);", program, StringComparison.Ordinal);
        Assert.Contains("pendingActivations.Add(args)", program, StringComparison.Ordinal);
        Assert.Contains("Application.Start", program, StringComparison.Ordinal);
        Assert.Contains("Program.Activated += HandleRedirectedActivation;", app, StringComparison.Ordinal);
        Assert.Contains("foreach (var activation in Program.TakePendingActivations())", app, StringComparison.Ordinal);
        Assert.Contains("pendingActivationArguments.Enqueue(args)", app, StringComparison.Ordinal);
        Assert.Contains("DrainPendingActivationArguments();", app, StringComparison.Ordinal);
        Assert.Contains("coordinator.HandleNotificationActivation(", app, StringComparison.Ordinal);
        Assert.DoesNotContain("coordinator?.HandleNotificationActivation(", app, StringComparison.Ordinal);
        Assert.Contains("public void HandleNotificationActivation(NotificationActivationArguments? parsed)", coordinator, StringComparison.Ordinal);
    }

    [Fact]
    public void StartupTaskManifestKeepsStartupOptInByDefault()
    {
        var manifest = XDocument.Load(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Package.appxmanifest"));
        XNamespace desktop = "http://schemas.microsoft.com/appx/manifest/desktop/windows10";
        var startupTask = manifest
            .Descendants(desktop + "StartupTask")
            .Single();

        Assert.Equal("PingWindowsStartup", startupTask.Attribute("TaskId")?.Value);
        Assert.Equal("false", startupTask.Attribute("Enabled")?.Value);
    }

    [Fact]
    public void WindowsCiRunsWhenSharedReleaseMetadataChanges()
    {
        var workflow = File.ReadAllText(Path.Combine(
            RepoRoot(),
            ".github",
            "workflows",
            "windows-client.yml"));

        Assert.Contains("\"windows/**\"", workflow, StringComparison.Ordinal);
        Assert.Contains("\"project.yml\"", workflow, StringComparison.Ordinal);
        Assert.Contains("\"README.md\"", workflow, StringComparison.Ordinal);
        Assert.Contains("\"PING_PROJECT_SPECIFICATION.md\"", workflow, StringComparison.Ordinal);
        Assert.Contains("\"docs/WINDOWS_APP_SETUP.md\"", workflow, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsCiUsesReleaseAndSmokeScriptsForPackaging()
    {
        var workflow = File.ReadAllText(Path.Combine(
            RepoRoot(),
            ".github",
            "workflows",
            "windows-client.yml"));

        Assert.Contains("windows\\scripts\\build-release.ps1", workflow, StringComparison.Ordinal);
        Assert.Contains("-Platform x64", workflow, StringComparison.Ordinal);
        Assert.Contains("-SkipTests", workflow, StringComparison.Ordinal);
        Assert.Contains("windows\\scripts\\smoke-release.ps1", workflow, StringComparison.Ordinal);
        Assert.Contains("-AllowUnsigned", workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("/p:GenerateAppxPackageOnBuild=true", workflow, StringComparison.Ordinal);
    }

    [Fact]
    public void OnboardingWindowRendersSecondaryActions()
    {
        var root = RepoRoot();
        var xaml = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Onboarding",
            "OnboardingWindow.xaml"));
        var code = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Onboarding",
            "OnboardingWindow.xaml.cs"));
        var converter = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Onboarding",
            "BooleanToVisibilityConverter.cs"));

        Assert.Contains("SecondaryActionButton_Click", xaml, StringComparison.Ordinal);
        Assert.Contains("SecondaryActionLabel", xaml, StringComparison.Ordinal);
        Assert.Contains("HasSecondaryAction", xaml, StringComparison.Ordinal);
        Assert.Contains("BooleanToVisibilityConverter", xaml, StringComparison.Ordinal);
        Assert.Contains("Visibility=\"{Binding HasPrimaryAction, Converter={StaticResource BooleanToVisibilityConverter}}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Visibility=\"{Binding HasSecondaryAction, Converter={StaticResource BooleanToVisibilityConverter}}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("SecondaryActionButton_Click", code, StringComparison.Ordinal);
        Assert.Contains("Visibility.Visible", converter, StringComparison.Ordinal);
        Assert.Contains("Visibility.Collapsed", converter, StringComparison.Ordinal);
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
