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
