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
using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Realtime;
using Ping.Windows.Core.Capture;

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
    private readonly IncomingChatPoller incomingChatPoller;
    private readonly IncomingObserver incomingObserver;
    private readonly RealtimeSupervisor realtime;
    private readonly IncomingVideoDelivery videoDelivery;
    private readonly IncomingDeliveryLedger chatDelivery = new();
    private readonly HashSet<string> yieldedChatIds = new(StringComparer.Ordinal);
    private readonly PlaybackPreparationQueue playbackPreparation;
    private readonly CancellationTokenSource lifetime = new();
    private readonly DateTimeOffset appStartedAt = DateTimeOffset.UtcNow;
    private readonly StartupIdentityGate startupIdentity = new();
    private bool realtimeWasConnected;
    private RealtimeConnectionState previousRealtimeState;
    private readonly NotificationController notificationController;
    private readonly IScreenFaceCaptureEngine screenFaceCaptureEngine;
    private readonly CameraOwnership camera;
    private readonly CaptureActivityState captureActivity = new(initiallyBlocked: true);
    private readonly AutoFaceReplyCoordinator autoFaceReply;
    private CaptureActivityAdapter? captureActivityAdapter;
    private readonly List<Task> cameraShutdowns = [];
    private readonly QuickSendController quickSendController;
    private readonly PermissionProbe permissionProbe;
    private readonly ScreenFaceQuickSendSettingsStore quickSendSettingsStore;
    private readonly MirrorPlacementStore mirrorPlacementStore;
    private readonly ConnectionSupervisor connectionSupervisor;
    private ConnectionLifecycleAdapter? connectionLifecycle;
    private IReadOnlyCollection<Room> rooms = [];
    private volatile string? currentUid;
    private string currentNickname = Environment.UserName;
    private string? remoteDefaultRoomId;
    private volatile ScreenFaceQuickSendSettings quickSendSettings;
    private IReadOnlyList<HotkeyRegistrationResult> lastHotkeyRegistrations = [];
    private FaceMirrorWindow? faceMirrorWindow;
    private ScreenFaceMirrorWindow? screenFaceMirrorWindow;
    private QuickSendHudWindow? quickSendHudWindow;
    private OnboardingWindow? onboardingWindow;
    private RoomManagerWindow? roomManagerWindow;
    private HistoryWindow? historyWindow;
    private SettingsWindow? settingsWindow;
    private readonly Dictionary<(string Uid, string Id), PlaybackWindow> playbackWindows = new();
    private CancellationTokenSource? quickSendCancellation;
    private TaskCompletionSource? quickSendFinished;
    private Task shutdown = Task.CompletedTask;
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
        incomingChatPoller = new IncomingChatPoller(chatService, roomService, () => currentUid, onError: HandleIncomingConnectionError);
        connectionSupervisor = new ConnectionSupervisor(ConnectAndLoadRoomsAsync);
        connectionSupervisor.StateChanged += HandleConnectionStateChanged;
        quickSendSettingsStore = new ScreenFaceQuickSendSettingsStore();
        mirrorPlacementStore = new MirrorPlacementStore();
        quickSendSettings = quickSendSettingsStore.Load();
        camera = new(() => quickSendSettings.Devices);
        UI.PingAppearance.Apply(quickSendSettings.AppearanceMode);
        notificationController = new NotificationController(OpenMessageFromNotificationAsync, OpenChatFromNotificationAsync,
            soundEnabled: () => quickSendSettings.NotificationSoundEnabled);
        realtime = new RealtimeSupervisor(this.supabaseClient.GetRealtimeCredentialsAsync,
            (_, _) => { incomingObserver!.Signal(); return Task.CompletedTask; });
        incomingObserver = new IncomingObserver(ReconcileIncomingAsync,
            () => TimeSpan.FromSeconds(realtime.State == RealtimeConnectionState.Connected ? 30 : 10), HandleIncomingConnectionError);
        realtime.StateChanged += HandleRealtimeStateChanged;
        realtime.RecoveryRequired += HandleIncomingConnectionError;
        playbackPreparation = new PlaybackPreparationQueue(DownloadVideoForPlaybackAsync, PresentPreparedPlaybackAsync,
            error => { HandleIncomingConnectionError(error); Debug.WriteLine("Ping playback preparation failed."); });
        screenFaceCaptureEngine = new OwnedScreenFaceCaptureEngine(camera, new NativeCaptureEngine());
        permissionProbe = new PermissionProbe(
            hotkeyBindingsProvider: preferencesStore.Load,
            activeHotkeyRegistrationsProvider: () => lastHotkeyRegistrations,
            cameraOwnership: camera);
        autoFaceReply = new(camera, captureActivity, appStartedAt,
            () => !disposed && currentUid is { } uid && connectionSupervisor.State is not (ConnectionState.SessionRejected or ConnectionState.ConfigurationRequired)
                ? new(uid, CurrentNickname, quickSendSettings.Preferences.AllowsLocalSave) : null,
            HasAutomaticCaptureAccess, RecordAutomaticReplyAsync, ShowAutoReplyIndicatorAsync,
            messageService.SendAutoReplyAsync, path => File.Delete(path), onError: _ => Debug.WriteLine("Ping automatic face reply failed."));
        videoDelivery = new IncomingVideoDelivery(appStartedAt, () => quickSendSettings.AutoPlayIncoming,
            ShowIncomingNotificationAsync, EnqueueAutomaticPlaybackAsync, messageService.MarkNotifiedAsync, HandleIncomingConnectionError);
        quickSendController = new QuickSendController(
            screenFaceCaptureEngine,
            SendVideoAndRememberRoomAsync,
            new CoordinatorQuickSendPresenter(this),
            () => quickSendSettings.Preferences,
            archive: localArchive);
        this.tray = tray ?? new TrayIconController(ExecuteTrayCommand);
        mainWindow.ScreenPingRequested += HandleScreenPingRequested;
        mainWindow.BlockedRetryRequested += HandleBlockedRetryRequested;
        mainWindow.OpenRoomsRequested += HandleOpenRoomsRequested;
        mainWindow.NewPingRequested += HandleNewPingRequested;
        mainWindow.OpenSettingsRequested += HandleOpenSettingsRequested;
    }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        OpenHistoryWindow();

        hotkeys.HotkeyPressed += HandleHotkeyPressed;
        lastHotkeyRegistrations = RegisterSavedHotkeys();
        TryAddOrUpdateTrayIcon();
        notificationController.Start();
        ShowRegistrationState(lastHotkeyRegistrations);
        MaybeOpenOnboardingAtStartup(lastHotkeyRegistrations);
        connectionLifecycle = new ConnectionLifecycleAdapter(connectionSupervisor);
        captureActivityAdapter = new(mainWindow, captureActivity);
        connectionSupervisor.Start();
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
            if (disposed) return;
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

        disposed = true;
        lifetime.Cancel();
        captureActivityAdapter?.Dispose();
        camera.InterruptAutomatic();
        faceMirrorWindow?.Close();
        screenFaceMirrorWindow?.Close();
        connectionLifecycle?.Dispose();
        connectionSupervisor.StateChanged -= HandleConnectionStateChanged;
        shutdown = DisposeConnectionAsync();
        hotkeys.HotkeyPressed -= HandleHotkeyPressed;
        mainWindow.ScreenPingRequested -= HandleScreenPingRequested;
        mainWindow.BlockedRetryRequested -= HandleBlockedRetryRequested;
        mainWindow.OpenRoomsRequested -= HandleOpenRoomsRequested;
        mainWindow.NewPingRequested -= HandleNewPingRequested;
        mainWindow.OpenSettingsRequested -= HandleOpenSettingsRequested;
        foreach (var window in playbackWindows.Values.ToArray()) window.Close();
        notificationController.Dispose();
        hotkeys.Dispose();
        quickSendCancellation?.Cancel();
        quickSendCancellation?.Dispose();
        tray.Dispose();
    }

    private async Task DisposeConnectionAsync()
    {
        await connectionSupervisor.StopAsync();
        await incomingObserver.DisposeAsync();
        await realtime.DisposeAsync();
        await playbackPreparation.DisposeAsync();
        await autoFaceReply.DisposeAsync();
        if (quickSendFinished is { } quick) await quick.Task;
        await Task.WhenAll(cameraShutdowns.ToArray());
        lifetime.Dispose();
        supabaseClient.Dispose();
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
                _ = QuitAsync();
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(command), command, "Unknown tray command.");
        }
    }

    private async Task QuitAsync()
    {
        Dispose();
        try { await shutdown; }
        catch { Debug.WriteLine("Ping shutdown cleanup failed."); }
        mainWindow.CloseForQuit();
        Application.Current.Exit();
    }

    private void HandleHotkeyPressed(object? sender, HotkeyCommand command)
    {
        Execute(command);
    }

    private void ShowHomeShell() => OpenHistoryWindow();

    private void ShowHistory(string detail) => OpenHistoryWindow();

    private void ShowBlockedState(string title, string detail, string reason, bool canRetry = false)
    {
        mainWindow.ReportStatus($"{title}: {reason}", canRetry);
    }

    private void ShowSettings() => OpenSettingsWindow();

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
            connectionSupervisor.RequestReconnect();
        };
        roomManagerWindow.Activate();
    }

    private void HandleRoomManagerRoomsChanged(object? sender, EventArgs args)
    {
        connectionSupervisor.RequestReconnect();
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
            mainWindow,
            new HistoryViewModel(
                roomService,
                messageService,
                chatService,
                reactionService,
                storageService,
                () => currentUid,
                canMarkRoomRead: roomId => historyWindow?.IsViewingRoom(roomId) == true),
            DownloadVideoForPlaybackAsync,
            SaveHistoryVideoAsync,
            messageService,
            preferredRoomId,
            preferredChatId,
            loadOnStart: currentUid is not null,
            playVideoAsync: (message, token) => RequestPlaybackAsync(message, IncomingArrivalSource.HistoryReplay, token));
        mainWindow.AttachMessenger(historyWindow);
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
            saveNickname: SaveProfileNicknameAsync,
            pairingGenerator: async token =>
            {
                if (currentUid is null) throw new InvalidOperationException("Ping session is not ready.");
                return PairingQrRenderer.Render(await this.supabaseClient.ExportDeviceHandoffAsync(token));
            }, pairingUid: () => currentUid));
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

    private void HandleScreenPingRequested(object? sender, EventArgs args) => Execute(HotkeyCommand.ScreenFacePing);

    private void HandleOpenSettingsRequested(object? sender, EventArgs args)
    {
        ShowSettings();
    }

    private void ApplyQuickSendSettings(ScreenFaceQuickSendSettings settings)
    {
        quickSendSettings = settings;
        quickSendSettingsStore.Save(quickSendSettings);
        UI.PingAppearance.Apply(quickSendSettings.AppearanceMode);
        RefreshDefaultRoomLabel();
    }

    private void RefreshDefaultRoomLabel()
    {
        var defaultRoom = currentUid is { } uid ? ResolvePreferredDefaultRoom(SendableRoomsFor(uid)) : null;
        mainWindow.ConfigureQuickSendSettings(
            quickSendSettings.Preferences.IsEnabled,
            defaultRoom?.Name ?? (currentUid is null ? "연결 후 기본 전송 방이 표시됩니다" : "전송할 수 있는 방이 없어요"));
    }

    private void ShowRegistrationState(IReadOnlyList<HotkeyRegistrationResult> registrations)
    {
        var failures = registrations
            .Where(result => result.Status != HotkeyRegistrationStatus.Success)
            .Select(result => $"{result.Binding}: {result.Message}")
            .ToArray();

        if (failures.Length == 0)
        {
            mainWindow.SetHotkeyStatus(HotkeyStatusText.Summary(preferencesStore.Load()));
            return;
        }

        mainWindow.SetHotkeyStatus(string.Join(Environment.NewLine, failures));
    }

    private HotkeyRegistrationResult ApplyHotkeySetting(HotkeyCommand command, HotkeyBinding binding)
    {
        var result = hotkeys.Register(command, binding);
        if (result.Status != HotkeyRegistrationStatus.Success)
        {
            mainWindow.SetHotkeyStatus($"{binding}: {result.Message}");
            return result;
        }

        var bindings = preferencesStore.Load()
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        bindings[command] = binding;
        preferencesStore.Save(bindings);
        UpdateHotkeyRegistrationResult(result);
        mainWindow.SetHotkeyStatus(HotkeyStatusText.Summary(bindings));

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

    private static bool HasAutomaticCaptureAccess()
    {
        try
        {
            return new[] { "Webcam", "Microphone" }.All(name =>
                global::Windows.Security.Authorization.AppCapabilityAccess.AppCapability.Create(name).CheckAccess()
                    == global::Windows.Security.Authorization.AppCapabilityAccess.AppCapabilityAccessStatus.Allowed);
        }
        catch (Exception error) when (error is System.Runtime.InteropServices.COMException or UnauthorizedAccessException) { return false; }
    }

    private async Task<string> RecordAutomaticReplyAsync(CameraLease lease, TimeSpan duration, CancellationToken token)
    {
        await using var recorder = new FaceRecorder(lease);
        Task<FaceRecordingResult>? recording = null;
        await RunOnUiThreadAsync(() =>
        {
            token.ThrowIfCancellationRequested();
            recording = recorder.RecordAsync(duration, token);
        });
        return (await (recording ?? throw new OperationCanceledException(token))).FilePath;
    }

    private async Task<IAsyncDisposable> ShowAutoReplyIndicatorAsync(VideoMessage message, CancellationToken token)
    {
        AutoReplyIndicatorWindow? indicator = null;
        await RunOnUiThreadAsync(() =>
        {
            token.ThrowIfCancellationRequested();
            if (disposed) throw new OperationCanceledException(token);
            indicator = new(message.SenderNickname);
            indicator.Present();
        });
        return indicator ?? throw new OperationCanceledException(token);
    }

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
        var lease = await camera.AcquireManualAsync(lifetime.Token)
            ?? throw new InvalidOperationException("다른 촬영이 카메라를 사용 중입니다. 촬영창을 닫고 다시 시도해 주세요.");
        try
        {
            if (disposed || currentUid != uid) throw new OperationCanceledException(lifetime.Token);
            var viewModel = new FaceMirrorViewModel(context, new FaceRecorder(lease), SendVideoAndRememberRoomAsync, localArchive);
            var window = new FaceMirrorWindow(viewModel, lease);
            faceMirrorWindow = window;
            window.Closed += (_, _) => { cameraShutdowns.Add(window.CameraShutdown); faceMirrorWindow = null; };
            window.Activate();
        }
        catch { lease.Dispose(); throw; }
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
        await ShowScreenFaceMirrorAsync(new ScreenFaceMirrorContext(
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

    private async Task ShowScreenFaceMirrorAsync(ScreenFaceMirrorContext context)
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

        var lease = await camera.AcquireManualAsync(lifetime.Token)
            ?? throw new InvalidOperationException("다른 촬영이 카메라를 사용 중입니다. 촬영창을 닫고 다시 시도해 주세요.");
        try
        {
            if (disposed || currentUid != context.SenderUid) throw new OperationCanceledException(lifetime.Token);
            var engine = new OwnedScreenFaceCaptureEngine(camera, new NativeCaptureEngine(), lease);
            var viewModel = new ScreenFaceMirrorViewModel(context, engine, SendVideoAndRememberRoomAsync, localArchive);
            var window = new ScreenFaceMirrorWindow(viewModel, lease);
            screenFaceMirrorWindow = window;
            window.Closed += (_, _) => { cameraShutdowns.Add(window.CameraShutdown); screenFaceMirrorWindow = null; };
            window.Activate();
        }
        catch { lease.Dispose(); throw; }
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
        quickSendFinished = new(TaskCreationOptions.RunContinuationsAsynchronously);

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
            quickSendFinished.TrySetResult();
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

        await RunOnUiThreadAsync(() =>
        {
            remoteDefaultRoomId = roomId;
            SaveQuickSendDefaultRoom(roomId);
        });
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
            RefreshDefaultRoomLabel();
            return;
        }

        quickSendSettings = quickSendSettings with { DefaultRoomId = roomId };
        quickSendSettingsStore.Save(quickSendSettings);
        RefreshDefaultRoomLabel();
    }

    private void HandleRealtimeStateChanged(RealtimeConnectionState state)
    {
        if (disposed) return;
        if (state == RealtimeConnectionState.FallbackPolling && previousRealtimeState == RealtimeConnectionState.Connected)
            incomingObserver.Signal(IncomingArrivalSource.ReconnectCatchUp);
        previousRealtimeState = state;
        if (state == RealtimeConnectionState.Connected)
        {
            incomingObserver.Signal(realtimeWasConnected ? IncomingArrivalSource.ReconnectCatchUp : IncomingArrivalSource.StartupCatchUp);
            realtimeWasConnected = true;
        }
    }

    private async Task ReconcileIncomingAsync(IncomingArrivalSource source, CancellationToken token)
    {
        using var reconciliation = CancellationTokenSource.CreateLinkedTokenSource(token, lifetime.Token);
        token = reconciliation.Token;
        var uid = currentUid;
        if (uid is null || disposed) return;
        var refreshedRooms = await roomService.MyRoomsAsync(token);
        await realtime.UpdateAsync(uid, refreshedRooms.Where(room => room.Id is not null && room.MemberUids.Contains(uid)).Select(room => room.Id!).ToArray(), cancellationToken: token);
        var messages = await messageService.IncomingAsync(token);
        foreach (var message in messages)
        {
            token.ThrowIfCancellationRequested();
            if (currentUid != uid || disposed) return;
            autoFaceReply.HandleIncoming(message, source);
            try { await videoDelivery.DeliverAsync(uid, message, source, token); }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
            catch (SupabaseSessionExpiredException) { throw; }
            catch (SupabaseSessionReadException) { throw; }
            catch (Exception error) { HandleIncomingConnectionError(error); }
        }
        await videoDelivery.RetryAcknowledgementsAsync(uid, token);
        foreach (var notification in await incomingChatPoller.LoadForDeliveryAsync(yieldedChatIds, token))
        {
            token.ThrowIfCancellationRequested();
            if (currentUid != uid || disposed) return;
            if (notification.Message.Id is not { Length: > 0 } id) continue;
            using var reservation = chatDelivery.TryReserve(uid, IncomingItemKind.Chat, id);
            if (reservation is null) continue;
            try
            {
                NotificationShowResult result = NotificationShowResult.Unavailable;
                await RunOnUiThreadAsync(() =>
                {
                    if (!disposed && currentUid == uid && !token.IsCancellationRequested)
                        result = notificationController.ShowIncomingChat(notification);
                });
                if (result == NotificationShowResult.Unavailable) continue;
                reservation.Commit();
                yieldedChatIds.Add(id);
                if (yieldedChatIds.Count > 512) yieldedChatIds.Clear();
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
            catch (Exception error) { HandleIncomingConnectionError(error); }
        }
        Task refresh = Task.CompletedTask;
        await RunOnUiThreadAsync(() =>
        {
            if (disposed || currentUid != uid || token.IsCancellationRequested) return;
            rooms = refreshedRooms;
            RefreshDefaultRoomLabel();
            if (historyWindow is { } history) refresh = history.ApplyIncomingRoomsAsync(refreshedRooms, token);
        });
        await refresh;
    }

    private async Task<IncomingNotificationResult> ShowIncomingNotificationAsync(VideoMessage message, CancellationToken token)
    {
        var result = NotificationShowResult.Unavailable;
        await RunOnUiThreadAsync(() =>
        {
            if (!disposed && currentUid == message.ReceiverUid && !token.IsCancellationRequested)
                result = notificationController.ShowIncoming(message);
        });
        return result switch
        {
            NotificationShowResult.Shown => IncomingNotificationResult.Shown,
            NotificationShowResult.Duplicate => IncomingNotificationResult.Duplicate,
            _ => IncomingNotificationResult.Unavailable
        };
    }

    private Task EnqueueAutomaticPlaybackAsync(VideoMessage message, IncomingArrivalSource source, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (!disposed && currentUid is { } uid && uid == message.ReceiverUid)
            playbackPreparation.Enqueue(uid, message, source);
        return Task.CompletedTask;
    }

    private async Task RequestPlaybackAsync(VideoMessage message, IncomingArrivalSource source, CancellationToken token)
    {
        if (disposed) return;
        var uid = currentUid ?? await startupIdentity.WaitAsync(token);
        if (disposed || currentUid != uid) return;
        await playbackPreparation.RequestAsync(uid, message, source, token);
    }

    private Task PresentPreparedPlaybackAsync(string uid, VideoMessage message, string path, IncomingArrivalSource source, CancellationToken token) =>
        RunOnUiThreadAsync(() =>
        {
            if (disposed || token.IsCancellationRequested || currentUid != uid) return;
            var decision = IncomingArrivalPolicy.Decide(message, uid, source, appStartedAt, DateTimeOffset.UtcNow, quickSendSettings.AutoPlayIncoming);
            if (decision.ShouldOpenPlayback) ShowPlayback(uid, message, path, source);
        });
    private async Task OpenMessageFromNotificationAsync(string messageId, CancellationToken cancellationToken)
    {
        using var activation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, lifetime.Token);
        cancellationToken = activation.Token;
        try
        {
            var message = await messageService.GetAsync(messageId, cancellationToken);
            if (message is null)
            {
                return;
            }

            await RequestPlaybackAsync(message, IncomingArrivalSource.NotificationClick, cancellationToken);
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

    private void ShowPlayback(string uid, VideoMessage message, string localVideoPath, IncomingArrivalSource source)
    {
        if (message.Id is null) return;
        var key = (uid, message.Id);
        if (playbackWindows.TryGetValue(key, out var existing))
        {
            if (source is IncomingArrivalSource.NotificationClick or IncomingArrivalSource.HistoryReplay) existing.Activate();
            return;
        }
        var viewModel = new PlaybackViewModel(
            message,
            localVideoPath,
            token => message.Id is null ? Task.CompletedTask : messageService.MarkSeenAsync(message.Id, token));
        var window = new PlaybackWindow(viewModel, mainWindow, historyReplay: source == IncomingArrivalSource.HistoryReplay);
        window.IsReplyGroupMember = message.IsAutoReply && source == IncomingArrivalSource.Live;
        playbackWindows[key] = window;
        window.Closed += (_, _) => { playbackWindows.Remove(key); RelayoutReplyGroup(window); };
        window.Activate();
        RelayoutReplyGroup(window);
    }

    private void RelayoutReplyGroup(PlaybackWindow anchor)
    {
        if (!anchor.IsReplyGroupMember) return;
        var message = anchor.ViewModel.Message;
        var group = playbackWindows.Values.Where(window => window.IsReplyGroupMember
            && window.ViewModel.Message.RoomId == message.RoomId
            && Math.Abs(window.ViewModel.Message.MirrorPosition.XRatio - message.MirrorPosition.XRatio) < .01
            && Math.Abs(window.ViewModel.Message.MirrorPosition.YRatio - message.MirrorPosition.YRatio) < .01).ToArray();
        var sizes = group.Select(window => PlaybackLayout.Single(window.ViewModel.Message.CaptureMode, window.ViewModel.Message.AspectRatio,
            message.MirrorPosition, anchor.WorkAreaDips, false)).ToArray();
        var layout = PlaybackLayout.Group(sizes, message.MirrorPosition, anchor.WorkAreaDips);
        for (var index = 0; index < group.Length; index++) group[index].ApplyPlacement(layout[index]);
    }

    private async Task OpenChatFromNotificationAsync(
        string chatId,
        string roomId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        await RunOnUiThreadAsync(() => OpenHistoryWindow(roomId, chatId));
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
            await RunOnUiThreadAsync(RefreshDefaultRoomLabel);
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

    private async Task ConnectAndLoadRoomsAsync(CancellationToken cancellationToken)
    {
        startupIdentity.PrepareRetry();
        var uid = await supabaseClient.BootstrapAsync(cancellationToken);
        var profile = await userService.GetAsync(uid, cancellationToken);
        var refreshedRooms = await roomService.MyRoomsAsync(cancellationToken);
        if (currentUid is { } previousUid && previousUid != uid)
        {
            await incomingObserver.StopAsync();
            camera.InterruptAutomatic();
            await autoFaceReply.WaitForIdleAsync();
            await realtime.StopAsync();
            yieldedChatIds.Clear();
            realtimeWasConnected = false;
            await RunOnUiThreadAsync(() =>
            {
                faceMirrorWindow?.Close();
                screenFaceMirrorWindow?.Close();
                quickSendCancellation?.Cancel();
                foreach (var window in playbackWindows.Values.ToArray()) window.Close();
            });
            if (quickSendFinished is { } quick) await quick.Task;
            await Task.WhenAll(cameraShutdowns.ToArray());
        }
        cancellationToken.ThrowIfCancellationRequested();
        await RunOnUiThreadAsync(() =>
        {
            if (disposed || cancellationToken.IsCancellationRequested) return;
            if (currentUid != uid) settingsWindow?.ClearDevicePairing();
            currentUid = uid;
            startupIdentity.SetReady(uid);
            if (!string.IsNullOrWhiteSpace(profile?.Nickname))
            {
                currentNickname = profile.Nickname;
                settingsWindow?.RefreshProfileNickname(CurrentNickname);
                roomManagerWindow?.RefreshProfileNickname(CurrentNickname);
            }

            remoteDefaultRoomId = profile?.LastUsedRoomId;
            rooms = refreshedRooms;
            if (ResolvePreferredDefaultRoom(SendableRoomsFor(uid)) is { Id: { } defaultRoomId })
            {
                SaveQuickSendDefaultRoom(defaultRoomId);
            }
            RefreshDefaultRoomLabel();

            var sendableCount = rooms.Count(room =>
                room.Id is not null
                && room.MemberUids.Contains(uid)
                && room.MemberUids.Count >= 2);

            mainWindow.SetHotkeyStatus(HotkeyStatusText.RoomSummary(preferencesStore.Load(), sendableCount));
            if (incomingObserver.IsRunning) incomingObserver.Signal(IncomingArrivalSource.ReconnectCatchUp);
            else incomingObserver.Start();

            if (historyWindow is not null) _ = historyWindow.ReloadRoomsAsync();
        });
        await realtime.UpdateAsync(uid, refreshedRooms.Where(room => room.Id is not null && room.MemberUids.Contains(uid)).Select(room => room.Id!).ToArray(),
            forceReconnect: realtime.State is RealtimeConnectionState.RecoveryRequired or RealtimeConnectionState.ConfigurationRequired,
            cancellationToken: cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        await RunCleanupAsync(cancellationToken);
    }

    private void HandleIncomingConnectionError(Exception error)
    {
        if (error is HttpRequestException or TimeoutException or OperationCanceledException or SupabaseSessionExpiredException or SupabaseSessionReadException)
            connectionSupervisor.ReportFailure(error);
    }

    private void HandleConnectionStateChanged(ConnectionState state, Exception? error)
    {
        _ = RunOnUiThreadAsync(() =>
        {
            if (disposed || state == ConnectionState.Stopped) return;
            if (state is ConnectionState.SessionRejected or ConnectionState.ConfigurationRequired)
            {
                settingsWindow?.ClearDevicePairing();
                camera.InterruptAutomatic();
                startupIdentity.Fail(error ?? new InvalidOperationException("Ping account startup failed."));
                _ = incomingObserver.StopAsync();
                _ = realtime.StopAsync();
            }
            var status = state switch
            {
                ConnectionState.Connecting => "연결하는 중…",
                ConnectionState.Connected => "연결됨",
                ConnectionState.Retrying => "연결이 끊겼습니다. 자동으로 다시 연결합니다.",
                ConnectionState.SessionRejected => "기존 계정을 보존했습니다. 계정 연결 복구가 필요합니다.",
                _ => "연결 설정을 확인해 주세요."
            };
            mainWindow.SetHotkeyStatus(status);
            mainWindow.ReportStatus(state == ConnectionState.Connected ? null : status,
                canRetry: state is ConnectionState.Retrying or ConnectionState.SessionRejected or ConnectionState.ConfigurationRequired);
            if (state is ConnectionState.SessionRejected or ConnectionState.ConfigurationRequired || currentUid is null)
            {
                ShowBlockedState("연결", status, error?.Message ?? status, canRetry: true);
            }
        });
    }

    private void HandleBlockedRetryRequested(object? sender, EventArgs args)
    {
        mainWindow.ReportStatus("다시 연결하는 중…");
        connectionSupervisor.RetryNow();
    }

    private async Task RunCleanupAsync(CancellationToken cancellationToken)
    {
        try
        {
            await cleanupService.RunAsync(cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception ex)
        {
            Debug.WriteLine($"Ping cleanup failed: {ex}");
        }

        cancellationToken.ThrowIfCancellationRequested();
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
            _ = owner.RunUiCommandAsync(() => owner.ShowScreenFaceMirrorAsync(context), "Screen+Face Ping");
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
