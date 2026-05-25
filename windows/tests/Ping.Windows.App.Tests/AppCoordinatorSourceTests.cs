using System.Security.Cryptography.X509Certificates;
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
    public void HistoryVideoRowsExposeMacStyleSaveActionWhenAllowed()
    {
        var root = RepoRoot();
        var rows = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "History",
            "HistoryRows.cs"));
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
        var coordinator = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "src",
            "Ping.Windows.App",
            "Bootstrap",
            "AppCoordinator.cs"));

        Assert.Contains("CanSave", rows, StringComparison.Ordinal);
        Assert.Contains("message.CanBeSavedLocally(currentUid)", rows, StringComparison.Ordinal);
        Assert.Contains("Click=\"SaveVideoButton_Click\"", xaml, StringComparison.Ordinal);
        Assert.Contains("Visibility=\"{Binding Video.SaveVisibility}\"", xaml, StringComparison.Ordinal);
        Assert.Contains("viewModel.SaveVideoAsync(item, saveVideoAsync)", code, StringComparison.Ordinal);
        Assert.Contains("SaveHistoryVideoAsync", coordinator, StringComparison.Ordinal);
        Assert.Contains("message.CanBeSavedLocally(currentUid)", coordinator, StringComparison.Ordinal);
        Assert.Contains("localArchive.SaveSentCopyAsync", coordinator, StringComparison.Ordinal);
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
            "Program.cs")).Replace("\r\n", "\n", StringComparison.Ordinal);
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
        Assert.Contains("new App();", program, StringComparison.Ordinal);
        Assert.DoesNotContain("_ = new App();", program, StringComparison.Ordinal);
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
    public void WindowsCiPublishesMsixArtifactsForReleaseValidation()
    {
        var workflow = File.ReadAllText(Path.Combine(
            RepoRoot(),
            ".github",
            "workflows",
            "windows-client.yml"));

        Assert.Contains("workflow_dispatch:", workflow, StringComparison.Ordinal);
        Assert.Contains("-Platform x64,ARM64", workflow, StringComparison.Ordinal);
        Assert.Contains("actions/upload-artifact", workflow, StringComparison.Ordinal);
        Assert.Contains("windows/dist/*.msix", workflow, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsFreeSideloadScriptsUseCertificateTrustAndArchitectureInstall()
    {
        var root = RepoRoot();
        var createCertificate = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "scripts",
            "create-sideload-certificate.ps1"));
        var install = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "scripts",
            "install-ping-windows.ps1"));
        var package = File.ReadAllText(Path.Combine(
            root,
            "windows",
            "scripts",
            "package-sideload-release.ps1"));

        Assert.Contains("CN=Youngmin Park", createCertificate, StringComparison.Ordinal);
        Assert.Contains("New-SelfSignedCertificate", createCertificate, StringComparison.Ordinal);
        Assert.Contains("Export-PfxCertificate", createCertificate, StringComparison.Ordinal);
        Assert.Contains("PING_WINDOWS_CERT_BASE64", createCertificate, StringComparison.Ordinal);
        Assert.Contains(@"Cert:\LocalMachine\TrustedPeople", install, StringComparison.Ordinal);
        Assert.Contains("Import-Certificate", install, StringComparison.Ordinal);
        Assert.Contains("Add-AppxPackage", install, StringComparison.Ordinal);
        Assert.Contains("ProcessArchitecture", install, StringComparison.Ordinal);
        Assert.Contains("Ping-Windows-v$Version-x64.msix", install, StringComparison.Ordinal);
        Assert.Contains("Ping-Windows-v$Version-arm64.msix", install, StringComparison.Ordinal);
        Assert.Contains("Get-AuthenticodeSignature", package, StringComparison.Ordinal);
        Assert.Contains("SHA256SUMS.txt", package, StringComparison.Ordinal);
        Assert.Contains("install-ping-windows.ps1", package, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsReleaseSmokeAcceptsExpectedSelfSignedSignerWithoutAllowUnsigned()
    {
        var script = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "scripts",
            "smoke-release.ps1"));

        Assert.Contains("Ping-Windows-Sideload.cer", script, StringComparison.Ordinal);
        Assert.Contains("Assert-TrustedPackageSignature", script, StringComparison.Ordinal);
        Assert.Contains("Test-SignatureMatchesTrustedCertificate", script, StringComparison.Ordinal);
        Assert.Contains("SignerCertificate.Thumbprint", script, StringComparison.Ordinal);
        Assert.Contains("Status -eq \"Valid\"", script, StringComparison.Ordinal);
        Assert.DoesNotContain("signature.Status -ne \"Valid\" -and -not $AllowUnsigned", script, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsSideloadPackagerAcceptsExpectedSelfSignedSignerWithoutAllowUnsigned()
    {
        var script = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "scripts",
            "package-sideload-release.ps1"));

        Assert.Contains("Test-SignatureMatchesTrustedCertificate", script, StringComparison.Ordinal);
        Assert.Contains("SignerCertificate.Thumbprint", script, StringComparison.Ordinal);
        Assert.Contains("Status -eq \"Valid\"", script, StringComparison.Ordinal);
        Assert.Contains("matches the committed Ping sideload certificate", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Package is not signed with a trusted certificate", script, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsSideloadPackagerUsesWildcardPathWhenCompressingReleaseBundle()
    {
        var script = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "scripts",
            "package-sideload-release.ps1"));

        Assert.Contains("Compress-Archive -Path", script, StringComparison.Ordinal);
        Assert.DoesNotContain("Compress-Archive -LiteralPath (Join-Path $releaseRoot \"*\")", script, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsFreeSideloadWorkflowImportsSigningSecretAndPublishesBundle()
    {
        var workflow = File.ReadAllText(Path.Combine(
            RepoRoot(),
            ".github",
            "workflows",
            "windows-client.yml"));

        Assert.Contains("PING_WINDOWS_CERT_BASE64", workflow, StringComparison.Ordinal);
        Assert.Contains("PING_WINDOWS_CERT_PASSWORD", workflow, StringComparison.Ordinal);
        Assert.Contains("PING_WINDOWS_CERT_THUMBPRINT", workflow, StringComparison.Ordinal);
        Assert.Contains("HasPrivateKey", workflow, StringComparison.Ordinal);
        Assert.Contains("PING_WINDOWS_SIGNED=true", workflow, StringComparison.Ordinal);
        Assert.Contains("package-sideload-release.ps1", workflow, StringComparison.Ordinal);
        Assert.Contains("ping-windows-sideload", workflow, StringComparison.Ordinal);
        Assert.Contains("publish_release", workflow, StringComparison.Ordinal);
        Assert.Contains("gh release upload", workflow, StringComparison.Ordinal);
        Assert.Contains("contents: write", workflow, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsFreeSideloadPublicCertificateIsCommittedWithoutPrivateKey()
    {
        var root = RepoRoot();
        var certificatePath = Path.Combine(root, "windows", "certs", "Ping-Windows-Sideload.cer");
        var certificate = X509CertificateLoader.LoadCertificateFromFile(certificatePath);

        Assert.Equal("CN=Youngmin Park", certificate.Subject);
        Assert.False(certificate.HasPrivateKey);
        Assert.False(File.Exists(Path.Combine(root, "windows", "certs", "Ping-Windows-Sideload.pfx")));
    }

    [Fact]
    public void WindowsReleaseBuildAvoidsParallelNativeProjectCollisions()
    {
        var script = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "scripts",
            "build-release.ps1"));

        Assert.Contains("$arguments.Add(\"/m:1\")", script, StringComparison.Ordinal);
        Assert.DoesNotContain("$arguments.Add(\"/m\")", script, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsReleaseBuildSignsAfterMsixPackagingWithSignTool()
    {
        var script = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "scripts",
            "build-release.ps1"));

        Assert.Contains("Resolve-SignTool", script, StringComparison.Ordinal);
        Assert.Contains("Sign-Package", script, StringComparison.Ordinal);
        Assert.Contains("signtool.exe", script, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("$Arguments.Add(\"/p:AppxPackageSigningEnabled=false\")", script, StringComparison.Ordinal);
        Assert.Contains("/fd", script, StringComparison.Ordinal);
        Assert.Contains("/f", script, StringComparison.Ordinal);
        Assert.Contains("/sha1", script, StringComparison.Ordinal);
        Assert.DoesNotContain("$Arguments.Add(\"/p:AppxPackageSigningEnabled=true\")", script, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsReleaseBuildAcceptsSdkGeneratedPackageNames()
    {
        var script = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "scripts",
            "build-release.ps1"));

        Assert.Contains("$_.Name", script, StringComparison.Ordinal);
        Assert.Contains("*_$architectureManifestValue.msix", script, StringComparison.Ordinal);
        Assert.Contains("Dependencies", script, StringComparison.Ordinal);
        Assert.DoesNotContain("YoungminPark.PingWindows_*", script, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsAppProjectPackagesNativeCaptureDll()
    {
        var project = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Ping.Windows.App.csproj"));

        Assert.Contains("CopyNativeCaptureDllToOutput", project, StringComparison.Ordinal);
        Assert.Contains("AddNativeCaptureDllToAppxPackage", project, StringComparison.Ordinal);
        Assert.Contains("BeforeTargets=\"_ComputeAppxPackagePayload\"", project, StringComparison.Ordinal);
        Assert.Contains("AppxPackagePayload", project, StringComparison.Ordinal);
        Assert.Contains(@"..\Ping.Windows.NativeCapture\bin\$(Platform)\$(Configuration)\$(TargetFramework)", project, StringComparison.Ordinal);
        Assert.Contains("Ping.Windows.NativeCapture.dll", project, StringComparison.Ordinal);
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

    [Fact]
    public void StartupOnboardingPolicyIncludesElevatedProcessState()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Bootstrap",
            "AppCoordinator.cs"));

        Assert.Contains("permissionProbe.IsElevated()", source, StringComparison.Ordinal);
        Assert.Contains("isElevated:", source, StringComparison.Ordinal);
    }

    [Fact]
    public void PlaybackWindowUsesWinUiCompatibleClipGeometry()
    {
        var source = File.ReadAllText(Path.Combine(
            RepoRoot(),
            "windows",
            "src",
            "Ping.Windows.App",
            "Playback",
            "PlaybackViewModel.cs"));

        Assert.Contains("new CornerRadius(size.Width / 2d)", source, StringComparison.Ordinal);
        Assert.Contains("new RectangleGeometry", source, StringComparison.Ordinal);
        Assert.Contains("new global::Windows.Foundation.Rect", source, StringComparison.Ordinal);
        Assert.DoesNotContain("new EllipseGeometry", source, StringComparison.Ordinal);
    }

    [Fact]
    public void AppSourcesQualifyWinRtNamespacesInsidePingWindowsNamespace()
    {
        var root = RepoRoot();
        var appRoot = Path.Combine(root, "windows", "src", "Ping.Windows.App");
        var unqualifiedWindowsNamespace = new System.Text.RegularExpressions.Regex(
            @"(?<!global::)(?<!Microsoft\.)(?<!Ping\.)\bWindows\.(ApplicationModel|Foundation|Graphics|Media|Security|Storage|System)\b",
            System.Text.RegularExpressions.RegexOptions.CultureInvariant);
        var violations = new List<string>();

        foreach (var file in Directory.EnumerateFiles(appRoot, "*.cs", SearchOption.AllDirectories))
        {
            var relativePath = Path.GetRelativePath(root, file);
            var lines = File.ReadAllLines(file);
            for (var index = 0; index < lines.Length; index++)
            {
                var line = lines[index];
                var trimmed = line.TrimStart();
                if (trimmed.StartsWith("using Windows.", StringComparison.Ordinal)
                    || trimmed.StartsWith("namespace Ping.Windows", StringComparison.Ordinal))
                {
                    continue;
                }

                if (unqualifiedWindowsNamespace.IsMatch(line))
                {
                    violations.Add($"{relativePath}:{index + 1}: {line.Trim()}");
                }
            }
        }

        Assert.Empty(violations);
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
