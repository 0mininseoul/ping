using Microsoft.UI.Xaml;
using Ping.Windows.App.Capture;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Onboarding;
using Ping.Windows.App.Notifications;
using Ping.Windows.App.Playback;
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
    private readonly IncomingMessagePoller incomingPoller;
    private readonly NotificationController notificationController;
    private readonly IScreenFaceCaptureEngine screenFaceCaptureEngine;
    private readonly QuickSendController quickSendController;
    private readonly PermissionProbe permissionProbe;
    private readonly ScreenFaceQuickSendSettingsStore quickSendSettingsStore;
    private IReadOnlyCollection<Room> rooms = [];
    private string? currentUid;
    private string? remoteDefaultRoomId;
    private ScreenFaceQuickSendSettings quickSendSettings;
    private FaceMirrorWindow? faceMirrorWindow;
    private ScreenFaceMirrorWindow? screenFaceMirrorWindow;
    private QuickSendHudWindow? quickSendHudWindow;
    private OnboardingWindow? onboardingWindow;
    private readonly List<PlaybackWindow> playbackWindows = [];
    private CancellationTokenSource? quickSendCancellation;
    private CancellationTokenSource? incomingPollingCancellation;
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
        incomingPoller = new IncomingMessagePoller(messageService);
        notificationController = new NotificationController(OpenMessageFromNotificationAsync);
        screenFaceCaptureEngine = new NativeCaptureEngine();
        permissionProbe = new PermissionProbe();
        quickSendSettingsStore = new ScreenFaceQuickSendSettingsStore();
        quickSendSettings = quickSendSettingsStore.Load();
        quickSendController = new QuickSendController(
            screenFaceCaptureEngine,
            SendVideoAndRememberRoomAsync,
            new CoordinatorQuickSendPresenter(this),
            () => quickSendSettings.Preferences,
            archive: new LocalArchive(LocalArchive.DefaultRootDirectory()));
        this.tray = tray ?? new TrayIconController(ExecuteTrayCommand);
        mainWindow.QuickSendToggleChanged += HandleQuickSendToggleChanged;
    }

    public void Start()
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        hotkeys.HotkeyPressed += HandleHotkeyPressed;
        var registrations = RegisterSavedHotkeys();
        tray.AddOrUpdateIcon();
        notificationController.Start();
        ShowHistory("Ping is running. Capture commands are wired and waiting for the capture windows.");
        ShowRegistrationState(registrations);
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
                ShowHistory("Alt+O reached Ping. Room history shell is visible.");
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(command), command, "Unknown Ping hotkey command.");
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
                ShowHistory("Tray opened Ping.");
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
        mainWindow.StateDetail.Text = "Configure screen+face quick send for Alt+Shift+L.";
        mainWindow.StateBorder.BorderBrush = mainWindow.IdleBorderBrush;
        mainWindow.HistoryPanel.Visibility = Visibility.Collapsed;
        mainWindow.BlockedPanel.Visibility = Visibility.Collapsed;
        mainWindow.SettingsPanel.Visibility = Visibility.Visible;
        mainWindow.ConfigureQuickSendSettings(
            quickSendSettings.Preferences.IsEnabled,
            defaultRoom?.Name ?? "No sendable default room");
        mainWindow.ShowShell();
    }

    private void HandleQuickSendToggleChanged(object? sender, bool isEnabled)
    {
        quickSendSettings = quickSendSettings with
        {
            Preferences = quickSendSettings.Preferences with { IsEnabled = isEnabled }
        };
        quickSendSettingsStore.Save(quickSendSettings);
        ShowSettings();
    }

    private void ShowRegistrationState(IReadOnlyList<HotkeyRegistrationResult> registrations)
    {
        var failures = registrations
            .Where(result => result.Status != HotkeyRegistrationStatus.Success)
            .Select(result => $"{result.Binding}: {result.Message}")
            .ToArray();

        if (failures.Length == 0)
        {
            mainWindow.HotkeyState.Text = "Alt+P face, Alt+L screen+face, Alt+Shift+L quick send, Alt+O history";
            return;
        }

        mainWindow.HotkeyState.Text = string.Join(Environment.NewLine, failures);
    }

    private void ShowFaceMirror()
    {
        var uid = currentUid;
        if (uid is null)
        {
            ShowBlockedState(
                "Face Ping",
                "Alt+P reached Ping. Supabase session is still starting or blocked by missing config.",
                "Supabase session not ready.");
            return;
        }

        var sendableRooms = SendableRoomsFor(uid);
        if (sendableRooms.Length == 0)
        {
            ShowBlockedState(
                "Face Ping",
                "Alt+P reached Ping. Create or join a room before sending a face ping.",
                "No sendable room available.");
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
            AllowsLocalSave: false,
            SaveSentCopy: false);
        var viewModel = new FaceMirrorViewModel(
            context,
            new FaceRecorder(),
            messageService,
            new LocalArchive(LocalArchive.DefaultRootDirectory()));

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
                "Alt+L reached Ping. Supabase session is still starting or blocked by missing config.",
                "Supabase session not ready.");
            return;
        }

        var sendableRooms = SendableRoomsFor(uid);
        if (sendableRooms.Length == 0)
        {
            ShowBlockedState(
                "Screen+Face Ping",
                "Alt+L reached Ping. Create or join a room before sending a screen+face ping.",
                "No sendable room available.");
            return;
        }

        ShowScreenFaceMirror(new ScreenFaceMirrorContext(
            Rooms: sendableRooms,
            SenderUid: uid,
            SenderNickname: Environment.UserName,
            PartnerLabel: PartnerLabelFor(sendableRooms),
            AllowsLocalSave: false,
            SaveSentCopy: false));
    }

    private void ShowScreenFaceMirror(ScreenFaceMirrorContext context)
    {
        if (screenFaceMirrorWindow is not null)
        {
            screenFaceMirrorWindow.Activate();
            return;
        }

        var viewModel = new ScreenFaceMirrorViewModel(
            context,
            screenFaceCaptureEngine,
            messageService,
            new LocalArchive(LocalArchive.DefaultRootDirectory()));

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
                "Alt+Shift+L reached Ping. Supabase session is still starting or blocked by missing config.",
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
                AllowsLocalSave: false,
                SaveSentCopy: false,
                MirrorPosition: new MirrorPosition(0.5, 0.5),
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

    private void StopIncomingPolling()
    {
        incomingPollingCancellation?.Cancel();
        incomingPollingCancellation = null;
    }

    private Task HandleIncomingMessageAsync(VideoMessage message, CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        notificationController.TryShowIncoming(message);
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

            var localVideoPath = await storageService.DownloadVideoAsync(message.VideoUrl, cancellationToken);
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
            var profile = await userService.GetAsync(uid);
            remoteDefaultRoomId = profile?.LastUsedRoomId;
            rooms = await supabaseClient.RpcArrayAsync<Room>("ping_my_rooms");
            if (ResolvePreferredDefaultRoom(SendableRoomsFor(uid)) is { Id: { } defaultRoomId })
            {
                SaveQuickSendDefaultRoom(defaultRoomId);
            }

            var sendableCount = rooms.Count(room =>
                room.Id is not null
                && room.MemberUids.Contains(uid)
                && room.MemberUids.Count >= 2);
            mainWindow.HotkeyState.Text =
                sendableCount == 0
                    ? "Alt+P ready, but no sendable room is available."
                    : $"Alt+P face, Alt+L screen+face, and Alt+Shift+L quick send ready for {sendableCount} room(s).";
            StartIncomingPolling();
        }
        catch (Exception ex)
        {
            mainWindow.HotkeyState.Text = $"Supabase setup blocked: {ex.Message}";
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
                "Alt+Shift+L reached Ping, but there is no sendable default room.",
                message);
        }

        public void ShowPermissionBlocked(QuickSendPermissionKind permission, string message)
        {
            if (owner.onboardingWindow is null)
            {
                owner.onboardingWindow = new OnboardingWindow();
                owner.onboardingWindow.Closed += (_, _) => owner.onboardingWindow = null;
            }

            owner.onboardingWindow.Activate();
            owner.ShowBlockedState(
                "Screen+Face permissions",
                $"Alt+Shift+L reached Ping, but {permission} is blocked. The onboarding checks are open.",
                message);
        }
    }
}
