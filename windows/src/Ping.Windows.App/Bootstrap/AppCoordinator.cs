using System.ComponentModel;
using System.Diagnostics;
using Microsoft.UI.Xaml;
using Ping.Windows.App.Capture;
using Ping.Windows.App.History;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Onboarding;
using Ping.Windows.App.Notifications;
using Ping.Windows.App.Playback;
using Ping.Windows.App.Setup;
using Ping.Windows.App.Tray;
using Ping.Windows.Core.Backend;
using Ping.Windows.Core.LocalState;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Bootstrap;

public sealed class AppCoordinator : IDisposable
{
    private readonly MainWindow mainWindow;
    private readonly HotkeyPreferencesStore preferencesStore;
    private readonly GlobalHotkeyManager hotkeys;
    private readonly TrayIconController tray;
    private readonly SupabaseClient supabaseClient;
    private readonly StorageService storageService;
    private readonly MessageService messageService;
    private readonly UserService userService;
    private readonly RoomService roomService;
    private readonly InvitationService invitationService;
    private readonly ChatMessageService chatService;
    private readonly ReactionService reactionService;
    private readonly CleanupService cleanupService;
    private readonly LocalArchive localArchive;
    private readonly IncomingMessagePoller incomingPoller;
    private readonly IncomingChatPoller incomingChatPoller;
    private readonly NotificationController notificationController;
    private readonly IScreenFaceCaptureEngine screenFaceCaptureEngine;
    private readonly QuickSendController quickSendController;
    private readonly PermissionProbe permissionProbe;
    private readonly ScreenFaceQuickSendSettingsStore quickSendSettingsStore;
    private readonly MirrorPlacementStore mirrorPlacementStore;
    private IReadOnlyCollection<Room> rooms = [];
    private string? currentUid;
    private string currentNickname = Environment.UserName;
    private string? remoteDefaultRoomId;
    private ScreenFaceQuickSendSettings quickSendSettings;
    private IReadOnlyList<HotkeyRegistrationResult> lastHotkeyRegistrations = [];
    private FaceMirrorWindow? faceMirrorWindow;
    private ScreenFaceMirrorWindow? screenFaceMirrorWindow;
    private QuickSendHudWindow? quickSendHudWindow;
    private OnboardingWindow? onboardingWindow;
    private RoomManagerWindow? roomManagerWindow;
    private HistoryWindow? historyWindow;
    private SettingsWindow? settingsWindow;
    private readonly List<PlaybackWindow> playbackWindows = [];
    private CancellationTokenSource? quickSendCancellation;
    private CancellationTokenSource? incomingPollingCancellation;
    private CancellationTokenSource? incomingChatPollingCancellation;
    private bool disposed;

    public AppCoordinator(MainWindow mainWindow)
        : this(
            mainWindow,
            new HotkeyPreferencesStore(),
            new GlobalHotkeyManager(),
            null,
            new SupabaseClient())
    {
    }

    internal AppCoordinator(
        MainWindow mainWindow,
        HotkeyPreferencesStore preferencesStore,
        GlobalHotkeyManager hotkeys,
        TrayIconController? tray,
        SupabaseClient? supabaseClient = null)
    {
        this.mainWindow = mainWindow;
        this.preferencesStore = preferencesStore;
        this.hotkeys = hotkeys;
        this.supabaseClient = supabaseClient ?? new SupabaseClient();
        storageService = new StorageService(this.supabaseClient);
        messageService = new MessageService(this.supabaseClient, storageService);
        userService = new UserService(this.supabaseClient);
        roomService = new RoomService(this.supabaseClient);
        invitationService = new InvitationService(this.supabaseClient);
        chatService = new ChatMessageService(this.supabaseClient);
        reactionService = new ReactionService(this.supabaseClient);
        cleanupService = new CleanupService(this.supabaseClient);
        localArchive = new LocalArchive(LocalArchive.DefaultRootDirectory());
        incomingPoller = new IncomingMessagePoller(messageService);
        incomingChatPoller = new IncomingChatPoller(chatService, roomService, () => currentUid);
        notificationController = new NotificationController(OpenMessageFromNotificationAsync, OpenChatFromNotificationAsync);
        screenFaceCaptureEngine = new NativeCaptureEngine();
        permissionProbe = new PermissionProbe(
            hotkeyBindingsProvider: preferencesStore.Load,
            activeHotkeyRegistrationsProvider: () => lastHotkeyRegistrations);
        quickSendSettingsStore = new ScreenFaceQuickSendSettingsStore();
        mirrorPlacementStore = new MirrorPlacementStore();
        quickSendSettings = quickSendSettingsStore.Load();
        quickSendController = new QuickSendController(
            screenFaceCaptureEngine,
            SendVideoAndRememberRoomAsync,
            new CoordinatorQuickSendPresenter(this),
            () => quickSendSettings.Preferences,
            archive: localArchive);
        this.tray = tray ?? new TrayIconController(ExecuteTrayCommand);
        mainWindow.QuickSendToggleChanged += HandleQuickSendToggleChanged;
        mainWindow.BlockedRetryRequested += HandleBlockedRetryRequested;
        mainWindow.OpenRoomsRequested += HandleOpenRoomsRequested;
        mainWindow.OpenHistoryRequested += HandleOpenHistoryRequested;
        mainWindow.NewPingRequested += HandleNewPingRequested;
        mainWindow.OpenSettingsRequested += HandleOpenSettingsRequested;
    }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        hotkeys.HotkeyPressed += HandleHotkeyPressed;
        lastHotkeyRegistrations = RegisterSavedHotkeys();
        TryAddOrUpdateTrayIcon();
        notificationController.Start();
        ShowRegistrationState(lastHotkeyRegistrations);
        MaybeOpenOnboardingAtStartup(lastHotkeyRegistrations);
        _ = BootstrapAndLoadRoomsAsync();
    }

    private void TryAddOrUpdateTrayIcon()
    {
        try
        {
            tray.AddOrUpdateIcon();
        }
        catch (Win32Exception)
        {
            Debug.WriteLine("Ping tray icon registration failed.");
        }
    }

    private string CurrentNickname =>
        string.IsNullOrWhiteSpace(currentNickname)
            ? Environment.UserName
            : currentNickname;

    public void Execute(HotkeyCommand command)
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        switch (command)
        {
            case HotkeyCommand.FacePing:
                _ = RunUiCommandAsync(ShowFaceMirrorAsync, "Face Ping");
                break;
            case HotkeyCommand.ScreenFacePing:
                _ = RunUiCommandAsync(ShowScreenFaceMirrorAsync, "Screen+Face Ping");
                break;
            case HotkeyCommand.QuickScreenFacePing:
                _ = RunUiCommandAsync(RunQuickScreenFacePingAsync, "Quick Screen+Face Ping");
                break;
            case HotkeyCommand.History:
                OpenHistoryWindow();
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(command), command, "Unknown Ping hotkey command.");
        }
    }

    private async Task RunUiCommandAsync(Func<Task> action, string title)
    {
        try
        {
            await action();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Ping {title} command failed: {ex}");
            ShowBlockedState(
                title,
                $"{title} reached Ping, but the command failed before the mirror could open.",
                ex.Message,
                canRetry: true);
        }
    }

    public void HandleInitialNotificationActivation()
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        HandleNotificationActivation(notificationController.TryGetInitialActivationArguments());
    }

    public void HandleNotificationActivation(NotificationActivationArguments? parsed)
    {
        if (parsed is null)
        {
            return;
        }

        if (string.Equals(parsed.Action, "play", StringComparison.Ordinal)
            && !string.IsNullOrWhiteSpace(parsed.MessageId))
        {
            _ = OpenMessageFromNotificationAsync(parsed.MessageId, CancellationToken.None);
            return;
        }

        if (string.Equals(parsed.Action, "chat", StringComparison.Ordinal)
            && !string.IsNullOrWhiteSpace(parsed.ChatId)
            && !string.IsNullOrWhiteSpace(parsed.RoomId))
        {
            _ = OpenChatFromNotificationAsync(parsed.ChatId, parsed.RoomId, CancellationToken.None);
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        hotkeys.HotkeyPressed -= HandleHotkeyPressed;
        mainWindow.QuickSendToggleChanged -= HandleQuickSendToggleChanged;
        mainWindow.BlockedRetryRequested -= HandleBlockedRetryRequested;
        mainWindow.OpenRoomsRequested -= HandleOpenRoomsRequested;
        mainWindow.OpenHistoryRequested -= HandleOpenHistoryRequested;
        mainWindow.NewPingRequested -= HandleNewPingRequested;
        mainWindow.OpenSettingsRequested -= HandleOpenSettingsRequested;
        StopIncomingPolling();
        StopIncomingChatPolling();
        notificationController.Dispose();
        supabaseClient.Dispose();
        hotkeys.Dispose();
        quickSendCancellation?.Cancel();
        quickSendCancellation?.Dispose();
        tray.Dispose();
        disposed = true;
    }

    private IReadOnlyList<HotkeyRegistrationResult> RegisterSavedHotkeys()
    {
        var bindings = preferencesStore.Load();
        var results = new List<HotkeyRegistrationResult>();
        foreach (var pair in bindings)
        {
            results.Add(hotkeys.Register(pair.Key, pair.Value));
        }

        return results;
    }

    private void ExecuteTrayCommand(TrayCommand command)
    {
        switch (command)
        {
            case TrayCommand.OpenPing:
                ShowHomeShell();
                break;
            case TrayCommand.NewFacePing:
                Execute(HotkeyCommand.FacePing);
                break;
            case TrayCommand.NewScreenFacePing:
                Execute(HotkeyCommand.ScreenFacePing);
                break;
            case TrayCommand.QuickScreenFacePing:
                Execute(HotkeyCommand.QuickScreenFacePing);
                break;
            case TrayCommand.Settings:
                ShowSettings();
                break;
            case TrayCommand.Quit:
                Dispose();
                mainWindow.CloseForQuit();
                Application.Current.Exit();
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(command), command, "Unknown tray command.");
        }
    }

    private void HandleHotkeyPressed(object? sender, HotkeyCommand command)
    {
        Execute(command);
    }

    private void ShowHomeShell()
    {
        mainWindow.ShellTitle.Text = "Ping";
        mainWindow.StateBadge.Text = "Ready";
        mainWindow.StateTitle.Text = "Ping is running";
        mainWindow.StateDetail.Text = "Close this window to keep Ping in the tray. Use the tray menu or hotkeys to send a ping.";
        mainWindow.StateBorder.BorderBrush = mainWindow.IdleBorderBrush;
        mainWindow.HistoryPanel.Visibility = Visibility.Visible;
        mainWindow.BlockedPanel.Visibility = Visibility.Collapsed;
        mainWindow.SettingsPanel.Visibility = Visibility.Collapsed;
        mainWindow.ShowShell();
    }

    private void ShowHistory(string detail)
    {
        mainWindow.ShellTitle.Text = "Ping";
        mainWindow.StateBadge.Text = "History";
        mainWindow.StateTitle.Text = "Rooms and recent pings";
        mainWindow.StateDetail.Text = detail;
        mainWindow.StateBorder.BorderBrush = mainWindow.IdleBorderBrush;
        mainWindow.HistoryPanel.Visibility = Visibility.Visible;
        mainWindow.BlockedPanel.Visibility = Visibility.Collapsed;
        mainWindow.SettingsPanel.Visibility = Visibility.Collapsed;
        mainWindow.ShowShell();
    }

    private void ShowBlockedState(string title, string detail, string reason, bool canRetry = false)
    {
        mainWindow.ShellTitle.Text = title;
        mainWindow.StateBadge.Text = "Blocked";
        mainWindow.StateTitle.Text = title;
        mainWindow.StateDetail.Text = detail;
        mainWindow.BlockedReason.Text = reason;
        mainWindow.BlockedRetryButton.Visibility = canRetry ? Visibility.Visible : Visibility.Collapsed;
        mainWindow.StateBorder.BorderBrush = mainWindow.WarningBorderBrush;
        mainWindow.HistoryPanel.Visibility = Visibility.Collapsed;
        mainWindow.BlockedPanel.Visibility = Visibility.Visible;
        mainWindow.SettingsPanel.Visibility = Visibility.Collapsed;
        mainWindow.ShowShell();
    }

    private void ShowSettings()
    {
        var uid = currentUid;
        var sendableRooms = uid is null ? Array.Empty<Room>() : SendableRoomsFor(uid);
        var defaultRoom = ResolvePreferredDefaultRoom(sendableRooms);

        mainWindow.ShellTitle.Text = "Settings";
        mainWindow.StateBadge.Text = "Settings";
        mainWindow.StateTitle.Text = "Windows quick send";
        mainWindow.StateDetail.Text = QuickSendSettingsDetail(preferencesStore.Load());
        mainWindow.StateBorder.BorderBrush = mainWindow.IdleBorderBrush;
        mainWindow.HistoryPanel.Visibility = Visibility.Collapsed;
        mainWindow.BlockedPanel.Visibility = Visibility.Collapsed;
        mainWindow.SettingsPanel.Visibility = Visibility.Visible;
        mainWindow.ConfigureQuickSendSettings(
            quickSendSettings.Preferences.IsEnabled,
            defaultRoom?.Name ?? "No sendable default room");
        mainWindow.ShowShell();

        // Keep Settings inside the stable main shell for now. The separate WinUI
        // SettingsWindow has caused Microsoft.UI.Xaml.dll crashes in packaged
        // builds on user machines, so opening it from the primary Settings button
        // is intentionally disabled until that window is rebuilt and covered by
        // a packaged UI smoke test.
    }

    private void OpenRoomManagerWindow()
    {
        if (roomManagerWindow is not null)
        {
            roomManagerWindow.RefreshProfileNickname(CurrentNickname);
            roomManagerWindow.Activate();
            return;
        }

        var viewModel = new RoomManagerViewModel(
            roomService,
            invitationService,
            CurrentNickname,
            userService: userService,
            currentUidProvider: () => currentUid);
        viewModel.RoomsChanged += HandleRoomManagerRoomsChanged;
        roomManagerWindow = new RoomManagerWindow(viewModel);
        roomManagerWindow.Closed += (_, _) =>
        {
            viewModel.RoomsChanged -= HandleRoomManagerRoomsChanged;
            roomManagerWindow = null;
            _ = BootstrapAndLoadRoomsAsync();
        };
        roomManagerWindow.Activate();
    }

    private void HandleRoomManagerRoomsChanged(object? sender, EventArgs args)
    {
        _ = BootstrapAndLoadRoomsAsync();
    }

    private void OpenHistoryWindow(string? preferredRoomId = null, string? preferredChatId = null)
    {
        if (historyWindow is not null)
        {
            historyWindow.Activate();
            if (!string.IsNullOrWhiteSpace(preferredRoomId) && !string.IsNullOrWhiteSpace(preferredChatId))
            {
                _ = historyWindow.FocusChatAsync(preferredRoomId, preferredChatId);
                return;
            }

            if (!string.IsNullOrWhiteSpace(preferredRoomId))
            {
                _ = historyWindow.FocusRoomAsync(preferredRoomId);
            }

            return;
        }

        historyWindow = new HistoryWindow(
            new HistoryViewModel(
                roomService,
                messageService,
                chatService,
                reactionService,
                storageService,
                () => currentUid),
            DownloadVideoForPlaybackAsync,
            SaveHistoryVideoAsync,
            messageService,
            preferredRoomId,
            preferredChatId);
        historyWindow.Closed += (_, _) => historyWindow = null;
        historyWindow.Activate();
    }

    private void OpenSettingsWindow(SettingsSection section = SettingsSection.General)
    {
        if (settingsWindow is not null)
        {
            settingsWindow.RefreshSettings(quickSendSettings);
            settingsWindow.RefreshProfileNickname(CurrentNickname);
            settingsWindow.ShowSection(section);
            settingsWindow.Activate();
            return;
        }

        settingsWindow = new SettingsWindow(new SettingsWindowViewModel(
            CurrentNickname,
            preferencesStore.Load(),
            quickSendSettings,
            ApplyQuickSendSettings,
            OpenRoomManagerWindow,
            updateHotkey: ApplyHotkeySetting,
            initialSection: section,
            archiveRootPath: localArchive.RootDirectory,
            ensureArchiveFolders: localArchive.EnsureFolders,
            deleteExpiredArchiveFiles: () => _ = localArchive.DeleteExpiredFiles(),
            openArchiveFolder: SettingsLauncher.LaunchFolderAsync,
            saveNickname: SaveProfileNicknameAsync));
        settingsWindow.Closed += (_, _) => settingsWindow = null;
        settingsWindow.Activate();
    }

    private void OpenOnboardingWindow()
    {
        if (onboardingWindow is null)
        {
            onboardingWindow = new OnboardingWindow(
                permissionProbe,
                () => OpenSettingsWindow(SettingsSection.Hotkeys));
            onboardingWindow.Closed += (_, _) => onboardingWindow = null;
        }

        onboardingWindow.Activate();
    }

    private void MaybeOpenOnboardingAtStartup(IReadOnlyList<HotkeyRegistrationResult> registrations)
    {
        if (OnboardingStartupPolicy.ShouldOpen(
            WindowsVersionProbe.CurrentStatus(),
            permissionProbe.IsSupabaseConfigured(),
            isElevated: permissionProbe.IsElevated(),
            registrations))
        {
            OpenOnboardingWindow();
        }
    }

    private void HandleQuickSendToggleChanged(object? sender, bool isEnabled)
    {
        ApplyQuickSendSettings(quickSendSettings with
        {
            Preferences = quickSendSettings.Preferences with { IsEnabled = isEnabled }
        });
        ShowSettings();
    }

    private void HandleOpenRoomsRequested(object? sender, EventArgs args)
    {
        OpenRoomManagerWindow();
    }

    private void HandleOpenHistoryRequested(object? sender, EventArgs args)
    {
        OpenHistoryWindow();
    }

    private void HandleNewPingRequested(object? sender, EventArgs args)
    {
        Execute(HotkeyCommand.FacePing);
    }

    private void HandleOpenSettingsRequested(object? sender, EventArgs args)
    {
        ShowSettings();
    }

    private void ApplyQuickSendSettings(ScreenFaceQuickSendSettings settings)
    {
        quickSendSettings = settings;
        quickSendSettingsStore.Save(quickSendSettings);
        var uid = currentUid;
        if (uid is null)
        {
            return;
        }

        var defaultRoom = ResolvePreferredDefaultRoom(SendableRoomsFor(uid));
        mainWindow.ConfigureQuickSendSettings(
            quickSendSettings.Preferences.IsEnabled,
            defaultRoom?.Name ?? "No sendable default room");
    }

    private void ShowRegistrationState(IReadOnlyList<HotkeyRegistrationResult> registrations)
    {
        var failures = registrations
            .Where(result => result.Status != HotkeyRegistrationStatus.Success)
            .Select(result => $"{result.Binding}: {result.Message}")
            .ToArray();

        if (failures.Length == 0)
        {
            mainWindow.HotkeyState.Text = HotkeyStatusText.Summary(preferencesStore.Load());
            return;
        }

        mainWindow.HotkeyState.Text = string.Join(Environment.NewLine, failures);
    }

    private HotkeyRegistrationResult ApplyHotkeySetting(HotkeyCommand command, HotkeyBinding binding)
    {
        var result = hotkeys.Register(command, binding);
        if (result.Status != HotkeyRegistrationStatus.Success)
        {
            mainWindow.HotkeyState.Text = $"{binding}: {result.Message}";
            return result;
        }

        var bindings = preferencesStore.Load()
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        bindings[command] = binding;
        preferencesStore.Save(bindings);
        UpdateHotkeyRegistrationResult(result);
        mainWindow.HotkeyState.Text = HotkeyStatusText.Summary(bindings);
        if (command == HotkeyCommand.QuickScreenFacePing && mainWindow.SettingsPanel.Visibility == Visibility.Visible)
        {
            mainWindow.StateDetail.Text = QuickSendSettingsDetail(bindings);
        }

        return result;
    }

    private void UpdateHotkeyRegistrationResult(HotkeyRegistrationResult result)
    {
        lastHotkeyRegistrations = lastHotkeyRegistrations
            .Where(existing => existing.Command != result.Command)
            .Append(result)
            .OrderBy(existing => existing.Command)
            .ToArray();
    }

    private string HotkeyLabel(HotkeyCommand command) =>
        HotkeyStatusText.BindingLabel(preferencesStore.Load(), command);

    private static string QuickSendSettingsDetail(IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> bindings) =>
        $"Configure screen+face quick send for {HotkeyStatusText.BindingLabel(bindings, HotkeyCommand.QuickScreenFacePing)}.";

    private async Task ShowFaceMirrorAsync()
    {
        var uid = currentUid;
        if (uid is null)
        {
            ShowBlockedState(
                "Face Ping",
                $"{HotkeyLabel(HotkeyCommand.FacePing)} reached Ping. Supabase session is still starting or blocked by missing config.",
                "Supabase session not ready.");
            return;
        }

        var sendableRooms = await SendableRoomsForCaptureAsync(uid);

        // Match macOS behavior: the capture mirror should open immediately and
        // surface camera/microphone problems inside the mirror instead of doing
        // a blocking MediaCapture preflight first. On Windows, MediaCapture
        // initialization can hang or wait behind privacy/device prompts before
        // any UI appears, which makes New face ping look dead.
        if (faceMirrorWindow is not null)
        {
            faceMirrorWindow.Activate();
            return;
        }

        var context = new FaceMirrorContext(
            Rooms: sendableRooms,
            SenderUid: uid,
            SenderNickname: CurrentNickname,
            PartnerLabel: PartnerLabelFor(sendableRooms),
            AllowsLocalSave: quickSendSettings.Preferences.AllowsLocalSave,
            SaveSentCopy: quickSendSettings.Preferences.SaveSentCopy,
            InitialPosition: mirrorPlacementStore.Load(CaptureMode.FaceOnly),
            SaveMirrorPosition: position => mirrorPlacementStore.Save(CaptureMode.FaceOnly, position));
        var viewModel = new FaceMirrorViewModel(
            context,
            new FaceRecorder(),
            SendVideoAndRememberRoomAsync,
            localArchive);

        faceMirrorWindow = new FaceMirrorWindow(viewModel);
        faceMirrorWindow.Closed += (_, _) => faceMirrorWindow = null;
        faceMirrorWindow.Activate();
    }

    private async Task ShowScreenFaceMirrorAsync()
    {
        var uid = currentUid;
        if (uid is null)
        {
            ShowBlockedState(
                "Screen+Face Ping",
                $"{HotkeyLabel(HotkeyCommand.ScreenFacePing)} reached Ping. Supabase session is still starting or blocked by missing config.",
                "Supabase session not ready.");
            return;
        }

        var sendableRooms = await SendableRoomsForCaptureAsync(uid);

        if (screenFaceMirrorWindow is not null)
        {
            screenFaceMirrorWindow.Activate();
            return;
        }

        // Keep screen+face consistent with macOS: show the mirror first, then let
        // the preview/record path report unavailable camera, microphone, or
        // screen capture state inside the mirror. Blocking preflight before the
        // window opens makes the Windows command feel broken when permission or
        // device checks stall.
        ShowScreenFaceMirror(new ScreenFaceMirrorContext(
            Rooms: sendableRooms,
            SenderUid: uid,
            SenderNickname: CurrentNickname,
            PartnerLabel: PartnerLabelFor(sendableRooms),
            AllowsLocalSave: quickSendSettings.Preferences.AllowsLocalSave,
            SaveSentCopy: quickSendSettings.Preferences.SaveSentCopy,
            InitialPosition: mirrorPlacementStore.Load(CaptureMode.ScreenFace),
            SaveMirrorPosition: position => mirrorPlacementStore.Save(CaptureMode.ScreenFace, position)));
    }

    private async Task<bool> EnsureCaptureReadyAsync(
        CaptureMode mode,
        string title,
        HotkeyCommand command)
    {
        var failure = await CapturePreflightFailureAsync(mode);
        if (failure is null)
        {
            return true;
        }

        OpenOnboardingWindow();
        ShowBlockedState(
            $"{title} permissions",
            $"{HotkeyLabel(command)} reached Ping, but {failure.Detail}",
            failure.Reason);
        return false;
    }

    private async Task<CapturePreflightFailure?> CapturePreflightFailureAsync(CaptureMode mode)
    {
        var windowsStatus = WindowsVersionProbe.CurrentStatus();
        if (windowsStatus != WindowsSupportStatus.Supported)
        {
            return CapturePreflight.FirstFailure(
                mode,
                windowsStatus,
                OnboardingProbeState.Unchecked("Camera was not checked because Windows is unsupported."),
                OnboardingProbeState.Unchecked("Microphone was not checked because Windows is unsupported."),
                OnboardingProbeState.Unchecked("Screen capture was not checked because Windows is unsupported."));
        }

        var ready = OnboardingProbeState.Available();
        var camera = await permissionProbe.CheckCameraAsync();
        if (CapturePreflight.FirstFailure(mode, windowsStatus, camera, ready, ready) is { } cameraFailure)
        {
            return cameraFailure;
        }

        var microphone = await permissionProbe.CheckMicrophoneAsync();
        if (CapturePreflight.FirstFailure(mode, windowsStatus, camera, microphone, ready) is { } microphoneFailure)
        {
            return microphoneFailure;
        }

        var screenCapture = mode == CaptureMode.ScreenFace
            ? await permissionProbe.CheckScreenCaptureAsync()
            : ready;

        return CapturePreflight.FirstFailure(mode, windowsStatus, camera, microphone, screenCapture);
    }

    private void ShowScreenFaceMirror(ScreenFaceMirrorContext context)
    {
        if (screenFaceMirrorWindow is not null)
        {
            screenFaceMirrorWindow.Activate();
            return;
        }

        context = context with
        {
            InitialPosition = context.InitialPosition ?? mirrorPlacementStore.Load(CaptureMode.ScreenFace),
            SaveMirrorPosition = context.SaveMirrorPosition
                ?? (position => mirrorPlacementStore.Save(CaptureMode.ScreenFace, position))
        };

        var viewModel = new ScreenFaceMirrorViewModel(
            context,
            screenFaceCaptureEngine,
            SendVideoAndRememberRoomAsync,
            localArchive);

        screenFaceMirrorWindow = new ScreenFaceMirrorWindow(viewModel);
        screenFaceMirrorWindow.Closed += (_, _) => screenFaceMirrorWindow = null;
        screenFaceMirrorWindow.Activate();
    }

    private async Task RunQuickScreenFacePingAsync()
    {
        var uid = currentUid;
        if (uid is null)
        {
            ShowBlockedState(
                "Quick Screen+Face",
                $"{HotkeyLabel(HotkeyCommand.QuickScreenFacePing)} reached Ping. Supabase session is still starting or blocked by missing config.",
                "Supabase session not ready.");
            return;
        }

        if (quickSendCancellation is not null)
        {
            quickSendCancellation.Cancel();
            return;
        }

        var cancellation = new CancellationTokenSource();
        quickSendCancellation = cancellation;

        try
        {
            if (!quickSendSettings.Preferences.IsEnabled)
            {
                await ShowScreenFaceMirrorAsync();
                return;
            }

            var sendableRooms = SendableRoomsFor(uid);
            var defaultRoom = ResolvePreferredDefaultRoom(sendableRooms);
            var preconditions = sendableRooms.Length > 0
                ? await LoadQuickSendPreconditionsAsync(cancellation.Token)
                : QuickSendPreconditions.Ready();
            var context = new QuickSendContext(
                Rooms: rooms,
                SenderUid: uid,
                SenderNickname: CurrentNickname,
                PartnerLabel: defaultRoom?.Name ?? "Default room",
                AllowsLocalSave: quickSendSettings.Preferences.AllowsLocalSave,
                SaveSentCopy: quickSendSettings.Preferences.SaveSentCopy,
                MirrorPosition: mirrorPlacementStore.Load(CaptureMode.ScreenFace),
                Preconditions: preconditions,
                DefaultRoomId: defaultRoom?.Id);
            _ = await quickSendController.ExecuteAsync(context, cancellation.Token);
        }
        finally
        {
            if (ReferenceEquals(quickSendCancellation, cancellation))
            {
                quickSendCancellation = null;
            }

            cancellation.Dispose();
        }
    }

    private async Task<QuickSendPreconditions> LoadQuickSendPreconditionsAsync(CancellationToken cancellationToken)
    {
        var windowsStatus = WindowsVersionProbe.CurrentStatus();
        if (windowsStatus != WindowsSupportStatus.Supported)
        {
            return new QuickSendPreconditions(
                IsCameraAvailable: false,
                IsMicrophoneAvailable: false,
                IsScreenCaptureAvailable: false,
                WindowsStatus: windowsStatus);
        }

        var camera = await permissionProbe.CheckCameraAsync(cancellationToken);
        var microphone = await permissionProbe.CheckMicrophoneAsync(cancellationToken);
        var screenCapture = await permissionProbe.CheckScreenCaptureAsync(cancellationToken);
        return new QuickSendPreconditions(
            IsCameraAvailable: camera.Status == OnboardingProbeStatus.Available,
            IsMicrophoneAvailable: microphone.Status == OnboardingProbeStatus.Available,
            IsScreenCaptureAvailable: screenCapture.Status == OnboardingProbeStatus.Available,
            WindowsStatus: windowsStatus);
    }

    private Room? ResolvePreferredDefaultRoom(IReadOnlyCollection<Room> sendableRooms)
    {
        if (sendableRooms.Count == 0)
        {
            return null;
        }

        foreach (var roomId in new[] { remoteDefaultRoomId, quickSendSettings.DefaultRoomId })
        {
            if (string.IsNullOrWhiteSpace(roomId))
            {
                continue;
            }

            var room = sendableRooms.FirstOrDefault(candidate =>
                string.Equals(candidate.Id, roomId, StringComparison.Ordinal));
            if (room is not null)
            {
                return room;
            }
        }

        return sendableRooms
            .OrderByDescending(room => room.CreatedAt ?? DateTimeOffset.MinValue)
            .ThenBy(room => room.Name, StringComparer.OrdinalIgnoreCase)
            .First();
    }

    private async Task SendVideoAndRememberRoomAsync(SendVideoInput input, CancellationToken cancellationToken)
    {
        await messageService.SendAsync(input, cancellationToken);

        if (input.Rooms.Count != 1 || input.Rooms.Single().Id is not { } roomId)
        {
            return;
        }

        remoteDefaultRoomId = roomId;
        SaveQuickSendDefaultRoom(roomId);
        try
        {
            await userService.UpdateLastUsedRoomAsync(roomId, cancellationToken);
        }
        catch (HttpRequestException)
        {
        }
        catch (InvalidOperationException)
        {
        }
    }

    private void SaveQuickSendDefaultRoom(string roomId)
    {
        if (string.Equals(quickSendSettings.DefaultRoomId, roomId, StringComparison.Ordinal))
        {
            return;
        }

        quickSendSettings = quickSendSettings with { DefaultRoomId = roomId };
        quickSendSettingsStore.Save(quickSendSettings);
    }

    private void StartIncomingPolling()
    {
        StopIncomingPolling();
        var cancellation = new CancellationTokenSource();
        incomingPollingCancellation = cancellation;

        _ = Task.Run(async () =>
        {
            try
            {
                await incomingPoller.RunAsync(HandleIncomingMessageAsync, cancellation.Token);
            }
            catch (OperationCanceledException)
            {
            }
            finally
            {
                cancellation.Dispose();
            }
        }, cancellation.Token);
    }

    private void StartIncomingChatPolling()
    {
        StopIncomingChatPolling();
        var cancellation = new CancellationTokenSource();
        incomingChatPollingCancellation = cancellation;

        _ = Task.Run(async () =>
        {
            try
            {
                await incomingChatPoller.RunAsync(HandleIncomingChatAsync, cancellation.Token);
            }
            catch (OperationCanceledException)
            {
            }
            finally
            {
                cancellation.Dispose();
            }
        }, cancellation.Token);
    }

    private void StopIncomingPolling()
    {
        incomingPollingCancellation?.Cancel();
        incomingPollingCancellation = null;
    }

    private void StopIncomingChatPolling()
    {
        incomingChatPollingCancellation?.Cancel();
        incomingChatPollingCancellation = null;
    }

    private async Task HandleIncomingMessageAsync(VideoMessage message, CancellationToken cancellationToken)
    {
        var notificationResult = notificationController.ShowIncoming(message);
        if (notificationResult == NotificationShowResult.Duplicate)
        {
            return;
        }

        await RefreshOpenHistoryRoomAsync(message.RoomId, cancellationToken);
        try
        {
            await OpenIncomingPlaybackAsync(message, cancellationToken);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            if (notificationResult == NotificationShowResult.Unavailable)
            {
                throw new InvalidOperationException("Incoming notification and playback are unavailable.", ex);
            }
        }
    }

    private async Task OpenIncomingPlaybackAsync(VideoMessage message, CancellationToken cancellationToken)
    {
        var localVideoPath = await DownloadVideoForPlaybackAsync(message, cancellationToken);
        await RunOnUiThreadAsync(() => ShowPlayback(message, localVideoPath));
    }

    private async Task HandleIncomingChatAsync(IncomingChatNotification notification, CancellationToken cancellationToken)
    {
        await RefreshOpenHistoryRoomAsync(notification.Message.RoomId, cancellationToken);
        if (notificationController.ShowIncomingChat(notification) == NotificationShowResult.Unavailable)
        {
            throw new InvalidOperationException("Incoming chat notification is unavailable.");
        }
    }

    private Task RefreshOpenHistoryRoomAsync(string? roomId, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(roomId) || historyWindow is null)
        {
            return Task.CompletedTask;
        }

        return RunOnUiThreadAsync(() =>
        {
            if (historyWindow is not { } window || !window.IsViewingRoom(roomId))
            {
                return;
            }

            _ = window.RefreshNowAsync(cancellationToken);
        });
    }

    private async Task OpenMessageFromNotificationAsync(string messageId, CancellationToken cancellationToken)
    {
        try
        {
            var message = await messageService.GetAsync(messageId, cancellationToken);
            if (message is null)
            {
                return;
            }

            var localVideoPath = await DownloadVideoForPlaybackAsync(message, cancellationToken);
            await RunOnUiThreadAsync(() => ShowPlayback(message, localVideoPath));
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            await RunOnUiThreadAsync(() =>
            {
                ShowBlockedState(
                    "Playback",
                    "Ping could not open the selected notification.",
                    ex.Message);
            });
        }
    }

    private void ShowPlayback(VideoMessage message, string localVideoPath)
    {
        var viewModel = new PlaybackViewModel(
            message,
            localVideoPath,
            token => message.Id is null ? Task.CompletedTask : messageService.MarkSeenAsync(message.Id, token));
        var window = new PlaybackWindow(viewModel);
        playbackWindows.Add(window);
        window.Closed += (_, _) => playbackWindows.Remove(window);
        window.Activate();
    }

    private async Task OpenChatFromNotificationAsync(
        string chatId,
        string roomId,
        CancellationToken cancellationToken)
    {
        await RunOnUiThreadAsync(() => OpenHistoryWindow(roomId, chatId));
        try
        {
            await chatService.MarkRoomReadAsync(roomId, cancellationToken);
        }
        catch (Exception ex) when (ex is HttpRequestException or InvalidOperationException)
        {
        }
    }

    private async Task<string> DownloadVideoForPlaybackAsync(
        VideoMessage message,
        CancellationToken cancellationToken)
    {
        if (ShouldSaveReceivedCopy(message)
            && localArchive.ExistingCopyPath(
                LocalArchiveKind.Received,
                message.SenderNickname,
                message.CreatedAt) is { } existingPath)
        {
            return existingPath;
        }

        var localVideoPath = await storageService.DownloadVideoAsync(message.VideoUrl, cancellationToken);
        if (!ShouldSaveReceivedCopy(message))
        {
            return localVideoPath;
        }

        try
        {
            var entry = await localArchive.SaveSentCopyAsync(
                localVideoPath,
                LocalArchiveKind.Received,
                message.SenderNickname,
                message.CreatedAt,
                cancellationToken);
            return entry.FilePath;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or InvalidOperationException)
        {
            return localVideoPath;
        }
    }

    private bool ShouldSaveReceivedCopy(VideoMessage message) =>
        quickSendSettings.Preferences.SaveReceivedCopy
        && message.CanBeSavedLocally(currentUid);

    private async Task SaveHistoryVideoAsync(
        VideoMessage message,
        CancellationToken cancellationToken)
    {
        if (!message.CanBeSavedLocally(currentUid))
        {
            throw new InvalidOperationException("Local save is not allowed for this video.");
        }

        var kind = string.Equals(message.SenderUid, currentUid, StringComparison.Ordinal)
            ? LocalArchiveKind.Sent
            : LocalArchiveKind.Received;
        var label = ArchiveLabelFor(message, kind);
        if (localArchive.ExistingCopyPath(kind, label, message.CreatedAt) is not null)
        {
            return;
        }

        var localVideoPath = await storageService.DownloadVideoAsync(message.VideoUrl, cancellationToken);
        if (localArchive.ExistingCopyPath(kind, label, message.CreatedAt) is not null)
        {
            return;
        }

        _ = await localArchive.SaveSentCopyAsync(
            localVideoPath,
            kind,
            label,
            message.CreatedAt,
            cancellationToken);
    }

    private string ArchiveLabelFor(VideoMessage message, LocalArchiveKind kind)
    {
        if (kind == LocalArchiveKind.Sent
            && rooms.FirstOrDefault(room => string.Equals(room.Id, message.RoomId, StringComparison.Ordinal))
                is { } room
            && room.MemberNicknames.TryGetValue(message.ReceiverUid, out var receiverNickname)
            && !string.IsNullOrWhiteSpace(receiverNickname))
        {
            return receiverNickname;
        }

        return message.SenderNickname;
    }

    private Task RunOnUiThreadAsync(Action action)
    {
        if (mainWindow.DispatcherQueue.HasThreadAccess)
        {
            action();
            return Task.CompletedTask;
        }

        var completion = new TaskCompletionSource();
        if (!mainWindow.DispatcherQueue.TryEnqueue(() =>
            {
                try
                {
                    action();
                    completion.SetResult();
                }
                catch (Exception ex)
                {
                    completion.SetException(ex);
                }
            }))
        {
            completion.SetException(new InvalidOperationException("Could not schedule Ping UI work."));
        }

        return completion.Task;
    }

    private Room[] SendableRoomsFor(string uid) =>
        rooms
            .Where(room => room.Id is not null && room.MemberUids.Contains(uid) && room.MemberUids.Count >= 2)
            .ToArray();

    private async Task<Room[]> SendableRoomsForCaptureAsync(string uid)
    {
        var sendableRooms = SendableRoomsFor(uid);
        if (sendableRooms.Length > 0)
        {
            return sendableRooms;
        }

        try
        {
            rooms = await roomService.MyRoomsAsync();
        }
        catch (Exception ex) when (ex is HttpRequestException or InvalidOperationException or TaskCanceledException)
        {
            Debug.WriteLine($"Ping room refresh before capture failed: {ex}");
        }

        return SendableRoomsFor(uid);
    }

    private static string PartnerLabelFor(IReadOnlyCollection<Room> sendableRooms) =>
        sendableRooms.Count switch
        {
            0 => "No partner",
            1 => sendableRooms.First().Name,
            _ => "All rooms"
        };

    private async Task BootstrapAndLoadRoomsAsync()
    {
        try
        {
            currentUid = await supabaseClient.BootstrapAsync();
            var uid = currentUid;
            await RunCleanupAsync();
            var profile = await userService.GetAsync(uid);
            if (!string.IsNullOrWhiteSpace(profile?.Nickname))
            {
                currentNickname = profile.Nickname;
                settingsWindow?.RefreshProfileNickname(CurrentNickname);
                roomManagerWindow?.RefreshProfileNickname(CurrentNickname);
            }

            remoteDefaultRoomId = profile?.LastUsedRoomId;
            rooms = await roomService.MyRoomsAsync();
            if (ResolvePreferredDefaultRoom(SendableRoomsFor(uid)) is { Id: { } defaultRoomId })
            {
                SaveQuickSendDefaultRoom(defaultRoomId);
            }

            var sendableCount = rooms.Count(room =>
                room.Id is not null
                && room.MemberUids.Contains(uid)
                && room.MemberUids.Count >= 2);
            if (mainWindow.HistoryPanel.Visibility == Visibility.Visible)
            {
                mainWindow.StateDetail.Text = sendableCount == 0
                    ? "Connected. Create or join a room to start sending."
                    : $"Connected. {sendableCount} sendable room(s) available.";
            }

            mainWindow.HotkeyState.Text = HotkeyStatusText.RoomSummary(preferencesStore.Load(), sendableCount);
            StartIncomingPolling();
            StartIncomingChatPolling();

            // 차단 화면에서 '다시 시도'로 재연결에 성공한 경우, 차단 상태를 벗어나
            // 연결된 화면을 보여준다.
            if (mainWindow.BlockedPanel.Visibility == Visibility.Visible)
            {
                ShowHistory(sendableCount == 0
                    ? "연결됨. 방을 만들거나 참여하면 전송할 수 있어요."
                    : $"연결됨. 전송 가능한 방 {sendableCount}개.");
            }
        }
        catch (Exception ex)
        {
            mainWindow.HotkeyState.Text = $"백엔드 연결 차단됨: {ex.Message}";
            ShowBlockedState(
                "백엔드 연결",
                "Ping이 백엔드에 연결하지 못했습니다. 인터넷 연결을 확인한 뒤 아래 '다시 시도'를 눌러주세요.",
                ex.Message,
                canRetry: true);
        }
    }

    private void HandleBlockedRetryRequested(object? sender, EventArgs args)
    {
        mainWindow.BlockedRetryButton.Visibility = Visibility.Collapsed;
        mainWindow.StateDetail.Text = "다시 연결하는 중...";
        _ = BootstrapAndLoadRoomsAsync();
    }

    private async Task RunCleanupAsync()
    {
        try
        {
            await cleanupService.RunAsync();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Ping cleanup failed: {ex}");
        }

        if (!quickSendSettings.Preferences.AutoDeleteAfter30Days)
        {
            return;
        }

        try
        {
            localArchive.EnsureFolders();
            _ = localArchive.DeleteExpiredFiles();
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Ping local archive cleanup failed: {ex}");
        }
    }

    private async Task<string> SaveProfileNicknameAsync(string nickname, CancellationToken cancellationToken)
    {
        var profile = await userService.UpsertAsync(nickname, cancellationToken);
        currentNickname = string.IsNullOrWhiteSpace(profile?.Nickname)
            ? nickname
            : profile.Nickname;
        roomManagerWindow?.RefreshProfileNickname(CurrentNickname);
        return CurrentNickname;
    }

    private sealed class CoordinatorQuickSendPresenter(AppCoordinator owner) : IQuickSendPresenter
    {
        public IQuickSendHudSession ShowHud(QuickSendHudContext context)
        {
            owner.quickSendHudWindow?.Close();
            var cancellation = owner.quickSendCancellation ?? new CancellationTokenSource();
            owner.quickSendCancellation ??= cancellation;
            owner.quickSendHudWindow = new QuickSendHudWindow(context, cancellation);
            owner.quickSendHudWindow.RetryRequested += (_, _) => owner.Execute(HotkeyCommand.QuickScreenFacePing);
            owner.quickSendHudWindow.Closed += (_, _) => owner.quickSendHudWindow = null;
            owner.quickSendHudWindow.Activate();
            return owner.quickSendHudWindow;
        }

        public void OpenScreenFaceMirror(ScreenFaceMirrorContext context)
        {
            owner.ShowScreenFaceMirror(context);
        }

        public void ShowRoomBlocked(string message)
        {
            owner.ShowBlockedState(
                "Rooms and recent pings",
                $"{owner.HotkeyLabel(HotkeyCommand.QuickScreenFacePing)} reached Ping, but there is no sendable default room.",
                message);
            owner.OpenRoomManagerWindow();
        }

        public void ShowPermissionBlocked(QuickSendPermissionKind permission, string message)
        {
            owner.OpenOnboardingWindow();
            var isWindowsBlocked = permission == QuickSendPermissionKind.WindowsVersion;
            owner.ShowBlockedState(
                isWindowsBlocked ? "Windows version" : "Screen+Face permissions",
                $"{owner.HotkeyLabel(HotkeyCommand.QuickScreenFacePing)} reached Ping, but {BlockedDetail(permission)}. The onboarding checks are open.",
                message);
        }

        private static string BlockedDetail(QuickSendPermissionKind permission) => permission switch
        {
            QuickSendPermissionKind.WindowsVersion => "this Windows version is not supported",
            QuickSendPermissionKind.ScreenCapture => "screen capture permission is blocked",
            QuickSendPermissionKind.Camera => "camera permission is blocked",
            QuickSendPermissionKind.Microphone => "microphone permission is blocked",
            _ => "a required permission is blocked"
        };
    }
}
