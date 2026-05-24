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
    }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        hotkeys.HotkeyPressed += HandleHotkeyPressed;
        lastHotkeyRegistrations = RegisterSavedHotkeys();
        tray.AddOrUpdateIcon();
        notificationController.Start();
        ShowRegistrationState(lastHotkeyRegistrations);
        MaybeOpenOnboardingAtStartup(lastHotkeyRegistrations);
        _ = BootstrapAndLoadRoomsAsync();
    }

    public void Execute(HotkeyCommand command)
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        switch (command)
        {
            case HotkeyCommand.FacePing:
                ShowFaceMirror();
                break;
            case HotkeyCommand.ScreenFacePing:
                ShowScreenFaceMirror();
                break;
            case HotkeyCommand.QuickScreenFacePing:
                _ = RunQuickScreenFacePingAsync();
                break;
            case HotkeyCommand.History:
                OpenHistoryWindow();
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(command), command, "Unknown Ping hotkey command.");
        }
    }

    public void HandleInitialNotificationActivation()
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        HandleNotificationActivation(notificationController.TryGetInitialActivationArguments());
    }

    private void HandleNotificationActivation(NotificationActivationArguments? parsed)
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
                OpenHistoryWindow();
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

    private void ShowBlockedState(string title, string detail, string reason)
    {
        mainWindow.ShellTitle.Text = title;
        mainWindow.StateBadge.Text = "Blocked";
        mainWindow.StateTitle.Text = title;
        mainWindow.StateDetail.Text = detail;
        mainWindow.BlockedReason.Text = reason;
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
        OpenSettingsWindow();
    }

    private void OpenRoomManagerWindow()
    {
        if (roomManagerWindow is not null)
        {
            roomManagerWindow.Activate();
            return;
        }

        roomManagerWindow = new RoomManagerWindow(new RoomManagerViewModel(
            roomService,
            invitationService,
            Environment.UserName));
        roomManagerWindow.Closed += (_, _) =>
        {
            roomManagerWindow = null;
            _ = BootstrapAndLoadRoomsAsync();
        };
        roomManagerWindow.Activate();
    }

    private void OpenHistoryWindow(string? preferredRoomId = null)
    {
        if (historyWindow is not null)
        {
            historyWindow.Activate();
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
            messageService,
            preferredRoomId);
        historyWindow.Closed += (_, _) => historyWindow = null;
        historyWindow.Activate();
    }

    private void OpenSettingsWindow(SettingsSection section = SettingsSection.General)
    {
        if (settingsWindow is not null)
        {
            settingsWindow.RefreshSettings(quickSendSettings);
            settingsWindow.ShowSection(section);
            settingsWindow.Activate();
            return;
        }

        settingsWindow = new SettingsWindow(new SettingsWindowViewModel(
            Environment.UserName,
            preferencesStore.Load(),
            quickSendSettings,
            ApplyQuickSendSettings,
            OpenRoomManagerWindow,
            updateHotkey: ApplyHotkeySetting,
            initialSection: section));
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

    private void ShowFaceMirror()
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

        var sendableRooms = SendableRoomsFor(uid);
        if (sendableRooms.Length == 0)
        {
            ShowBlockedState(
                "Face Ping",
                $"{HotkeyLabel(HotkeyCommand.FacePing)} reached Ping. Create or join a room before sending a face ping.",
                "No sendable room available.");
            OpenRoomManagerWindow();
            return;
        }

        if (faceMirrorWindow is not null)
        {
            faceMirrorWindow.Activate();
            return;
        }

        var context = new FaceMirrorContext(
            Rooms: sendableRooms,
            SenderUid: uid,
            SenderNickname: Environment.UserName,
            PartnerLabel: sendableRooms.Length == 1 ? sendableRooms[0].Name : "All rooms",
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

    private void ShowScreenFaceMirror()
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

        var sendableRooms = SendableRoomsFor(uid);
        if (sendableRooms.Length == 0)
        {
            ShowBlockedState(
                "Screen+Face Ping",
                $"{HotkeyLabel(HotkeyCommand.ScreenFacePing)} reached Ping. Create or join a room before sending a screen+face ping.",
                "No sendable room available.");
            OpenRoomManagerWindow();
            return;
        }

        ShowScreenFaceMirror(new ScreenFaceMirrorContext(
            Rooms: sendableRooms,
            SenderUid: uid,
            SenderNickname: Environment.UserName,
            PartnerLabel: PartnerLabelFor(sendableRooms),
            AllowsLocalSave: quickSendSettings.Preferences.AllowsLocalSave,
            SaveSentCopy: quickSendSettings.Preferences.SaveSentCopy,
            InitialPosition: mirrorPlacementStore.Load(CaptureMode.ScreenFace),
            SaveMirrorPosition: position => mirrorPlacementStore.Save(CaptureMode.ScreenFace, position)));
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

        quickSendCancellation?.Cancel();
        var cancellation = new CancellationTokenSource();
        quickSendCancellation = cancellation;

        try
        {
            var sendableRooms = SendableRoomsFor(uid);
            var defaultRoom = ResolvePreferredDefaultRoom(sendableRooms);
            var preconditions = sendableRooms.Length > 0 && quickSendSettings.Preferences.IsEnabled
                ? await LoadQuickSendPreconditionsAsync(cancellation.Token)
                : QuickSendPreconditions.Ready();
            var context = new QuickSendContext(
                Rooms: rooms,
                SenderUid: uid,
                SenderNickname: Environment.UserName,
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
        var isSupportedWindows = WindowsVersionProbe.CurrentStatus() == WindowsSupportStatus.Supported;
        if (!isSupportedWindows)
        {
            return new QuickSendPreconditions(
                IsCameraAvailable: false,
                IsMicrophoneAvailable: false,
                IsScreenCaptureAvailable: false);
        }

        var camera = await permissionProbe.CheckCameraAsync(cancellationToken);
        var microphone = await permissionProbe.CheckMicrophoneAsync(cancellationToken);
        var screenCapture = await permissionProbe.CheckScreenCaptureAsync(cancellationToken);
        return new QuickSendPreconditions(
            IsCameraAvailable: camera.Status == OnboardingProbeStatus.Available,
            IsMicrophoneAvailable: microphone.Status == OnboardingProbeStatus.Available,
            IsScreenCaptureAvailable: screenCapture.Status == OnboardingProbeStatus.Available);
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

    private Task HandleIncomingMessageAsync(VideoMessage message, CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        notificationController.TryShowIncoming(message);
        return Task.CompletedTask;
    }

    private Task HandleIncomingChatAsync(IncomingChatNotification notification, CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        notificationController.TryShowIncomingChat(notification);
        return Task.CompletedTask;
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
        _ = chatId;
        await RunOnUiThreadAsync(() => OpenHistoryWindow(roomId));
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

    private static string PartnerLabelFor(IReadOnlyCollection<Room> sendableRooms) =>
        sendableRooms.Count == 1 ? sendableRooms.First().Name : "All rooms";

    private async Task BootstrapAndLoadRoomsAsync()
    {
        try
        {
            currentUid = await supabaseClient.BootstrapAsync();
            var uid = currentUid;
            await RunCleanupAsync();
            var profile = await userService.GetAsync(uid);
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
        }
        catch (Exception ex)
        {
            mainWindow.HotkeyState.Text = $"Supabase setup blocked: {ex.Message}";
            ShowBlockedState(
                "Supabase setup",
                "Ping could not connect to Supabase. Check your Windows runtime config and network, then retry from onboarding or relaunch Ping.",
                ex.Message);
        }
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
            owner.ShowBlockedState(
                "Screen+Face permissions",
                $"{owner.HotkeyLabel(HotkeyCommand.QuickScreenFacePing)} reached Ping, but {permission} is blocked. The onboarding checks are open.",
                message);
        }
    }
}
