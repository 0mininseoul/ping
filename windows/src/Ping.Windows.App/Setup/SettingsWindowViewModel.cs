using System.ComponentModel;
using System.Collections.ObjectModel;
using System.Runtime.CompilerServices;
using Ping.Windows.App.Capture;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Onboarding;
using Ping.Windows.Core.LocalState;
using Ping.Windows.Core.Models;
using Ping.Windows.Core.Backend;

#if WINDOWS
using Microsoft.UI.Xaml;
#endif

namespace Ping.Windows.App.Setup;

public enum SettingsSection
{
    General = 0,
    Hotkeys = 1,
    Rooms = 2,
    Storage = 3,
    Devices = 4,
    Info = 5
}

public sealed class SettingsWindowViewModel : INotifyPropertyChanged
{
    private readonly Action<ScreenFaceQuickSendSettings> saveSettings;
    private readonly Action openRooms;
    private readonly Action ensureArchiveFolders;
    private readonly Action deleteExpiredArchiveFiles;
    private readonly Func<string, Task<bool>> openArchiveFolder;
    private readonly Func<string, CancellationToken, Task<string>> saveNickname;
    private readonly IStartupTaskController startupTaskController;
    private readonly Func<HotkeyCommand, HotkeyBinding, HotkeyRegistrationResult> updateHotkey;
    private readonly Dictionary<HotkeyCommand, HotkeyBinding> hotkeys;
    private ScreenFaceQuickSendSettings settings;
    private bool isStartupEnabled;
    private bool canToggleStartup;
    private bool isSavingNickname;
    private string nickname;
    private string nicknameDraft;
    private string nicknameStatus = "룸 멤버와 메시지를 받는 친구에게 표시됩니다.";
    private string startupStatus = "자동 시작 설정을 확인하고 있어요…";
    private string faceHotkey;
    private string screenFaceHotkey;
    private string quickSendHotkey;
    private string historyHotkey;
    private string quickSendOffContent;
    private string quickSendOnContent;
    private string archiveFolderStatus = string.Empty;
    private int selectedTabIndex;

    public SettingsWindowViewModel(
        string nickname,
        IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> hotkeys,
        ScreenFaceQuickSendSettings settings,
        Action<ScreenFaceQuickSendSettings> saveSettings,
        Action openRooms,
        IStartupTaskController? startupTaskController = null,
        Func<HotkeyCommand, HotkeyBinding, HotkeyRegistrationResult>? updateHotkey = null,
        SettingsSection initialSection = SettingsSection.General,
        string? archiveRootPath = null,
        Action? ensureArchiveFolders = null,
        Action? deleteExpiredArchiveFiles = null,
        Func<string, Task<bool>>? openArchiveFolder = null,
        Func<string, CancellationToken, Task<string>>? saveNickname = null,
        Func<CancellationToken, Task<CaptureDeviceCatalog>>? deviceCatalog = null,
        Func<CancellationToken, Task<PairingQrImage>>? pairingGenerator = null, Func<string?>? pairingUid = null,
        Func<CancellationToken, Task<IReadOnlyList<StoredAccountSummary>>>? loadAccounts = null,
        Func<AccountChange, CancellationToken, Task>? changeAccount = null,
        UpdateSettingsViewModel? updates = null)
    {
        this.nickname = NormalizeNickname(nickname);
        nicknameDraft = this.nickname;
        selectedTabIndex = (int)initialSection;
        ArchiveRootPath = Path.GetFullPath(archiveRootPath ?? LocalArchive.DefaultRootDirectory());
        this.hotkeys = hotkeys.ToDictionary(pair => pair.Key, pair => pair.Value);
        this.settings = settings;
        this.saveSettings = saveSettings;
        Devices = new(settings.Devices, value =>
        {
            this.settings = this.settings with { Devices = value };
            this.saveSettings(this.settings);
        }, deviceCatalog);
        Pairing = new(pairingGenerator ?? (_ => throw new InvalidOperationException("Pairing session is unavailable.")), pairingUid ?? (() => null));
        Accounts = new(loadAccounts ?? (_ => Task.FromResult<IReadOnlyList<StoredAccountSummary>>([])),
            changeAccount ?? ((_, _) => throw new InvalidOperationException("Account management is unavailable.")));
#if WINDOWS
        Updates = updates ?? WindowsUpdateController.CreateViewModel();
#else
        Updates = updates ?? new("로컬 개발 빌드", _ => throw new InvalidOperationException(), (_, _, _) => Task.CompletedTask);
#endif
        this.openRooms = openRooms;
        this.ensureArchiveFolders = ensureArchiveFolders ?? (() => new LocalArchive(ArchiveRootPath).EnsureFolders());
        this.deleteExpiredArchiveFiles = deleteExpiredArchiveFiles ?? (() => _ = new LocalArchive(ArchiveRootPath).DeleteExpiredFiles());
        this.openArchiveFolder = openArchiveFolder ?? SettingsLauncher.LaunchFolderAsync;
        this.saveNickname = saveNickname ?? ((value, _) => Task.FromResult(NormalizeNickname(value)));
        this.startupTaskController = startupTaskController ?? new StartupTaskController();
        this.updateHotkey = updateHotkey ?? ((command, binding) => HotkeyRegistrationResult.Success(command, binding));
        faceHotkey = LabelFor("얼굴 Ping", this.hotkeys, HotkeyCommand.FacePing);
        screenFaceHotkey = LabelFor("화면+얼굴 Ping", this.hotkeys, HotkeyCommand.ScreenFacePing);
        quickSendHotkey = LabelFor("화면+얼굴 빠른 전송", this.hotkeys, HotkeyCommand.QuickScreenFacePing);
        historyHotkey = LabelFor("메신저", this.hotkeys, HotkeyCommand.History);
        quickSendOffContent = QuickSendModeText("거울 열기", this.hotkeys);
        quickSendOnContent = QuickSendModeText("바로 녹화", this.hotkeys);
        HotkeyRows = new ObservableCollection<HotkeySettingRow>(
            HotkeySettingRow.FromBindings(this.hotkeys));
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public DeviceSettingsViewModel Devices { get; }
    public DevicePairingViewModel Pairing { get; }
    public AccountSettingsViewModel Accounts { get; }
    public UpdateSettingsViewModel Updates { get; }

    public bool AutoPlayIncoming
    {
        get => settings.AutoPlayIncoming;
        set
        {
            if (settings.AutoPlayIncoming == value) return;
            settings = settings with { AutoPlayIncoming = value };
            saveSettings(settings);
            OnPropertyChanged();
        }
    }

    public bool NotificationSoundEnabled
    {
        get => settings.NotificationSoundEnabled;
        set
        {
            if (settings.NotificationSoundEnabled == value) return;
            settings = settings with { NotificationSoundEnabled = value };
            saveSettings(settings); OnPropertyChanged();
        }
    }

    public int AppearanceSelection
    {
        get => Enum.IsDefined(settings.AppearanceMode) ? (int)settings.AppearanceMode : 0;
        set
        {
            if (value < 0 || value > 2 || AppearanceSelection == value) return;
            settings = settings with { AppearanceMode = (PingAppearanceMode)value };
            saveSettings(settings); OnPropertyChanged();
        }
    }

    public string Nickname
    {
        get => nickname;
        private set
        {
            if (string.Equals(nickname, value, StringComparison.Ordinal))
            {
                return;
            }

            nickname = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanSaveNickname));
        }
    }

    public string NicknameDraft
    {
        get => nicknameDraft;
        set
        {
            if (string.Equals(nicknameDraft, value, StringComparison.Ordinal))
            {
                return;
            }

            nicknameDraft = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanSaveNickname));
        }
    }

    public string NicknameStatus
    {
        get => nicknameStatus;
        private set
        {
            if (string.Equals(nicknameStatus, value, StringComparison.Ordinal))
            {
                return;
            }

            nicknameStatus = value;
            OnPropertyChanged();
        }
    }

    public bool IsSavingNickname
    {
        get => isSavingNickname;
        private set
        {
            if (isSavingNickname == value)
            {
                return;
            }

            isSavingNickname = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(CanSaveNickname));
        }
    }

    public bool CanSaveNickname =>
        !IsSavingNickname
        && !string.IsNullOrWhiteSpace(NormalizeNickname(NicknameDraft))
        && !string.Equals(NormalizeNickname(NicknameDraft), Nickname, StringComparison.Ordinal);

    public string ArchiveRootPath { get; }

    public int SelectedTabIndex
    {
        get => selectedTabIndex;
        set
        {
            if (selectedTabIndex == value)
            {
                return;
            }

            selectedTabIndex = value;
            OnPropertyChanged();
        }
    }

    public string FaceHotkey
    {
        get => faceHotkey;
        private set
        {
            if (faceHotkey == value)
            {
                return;
            }

            faceHotkey = value;
            OnPropertyChanged();
        }
    }

    public string ScreenFaceHotkey
    {
        get => screenFaceHotkey;
        private set
        {
            if (screenFaceHotkey == value)
            {
                return;
            }

            screenFaceHotkey = value;
            OnPropertyChanged();
        }
    }

    public string QuickSendHotkey
    {
        get => quickSendHotkey;
        private set
        {
            if (quickSendHotkey == value)
            {
                return;
            }

            quickSendHotkey = value;
            OnPropertyChanged();
        }
    }

    public string HistoryHotkey
    {
        get => historyHotkey;
        private set
        {
            if (historyHotkey == value)
            {
                return;
            }

            historyHotkey = value;
            OnPropertyChanged();
        }
    }

    public string QuickSendOffContent
    {
        get => quickSendOffContent;
        private set
        {
            if (quickSendOffContent == value)
            {
                return;
            }

            quickSendOffContent = value;
            OnPropertyChanged();
        }
    }

    public string QuickSendOnContent
    {
        get => quickSendOnContent;
        private set
        {
            if (quickSendOnContent == value)
            {
                return;
            }

            quickSendOnContent = value;
            OnPropertyChanged();
        }
    }

    public ObservableCollection<HotkeySettingRow> HotkeyRows { get; }

    public string StartupStatus
    {
        get => startupStatus;
        private set
        {
            if (startupStatus == value)
            {
                return;
            }

            startupStatus = value;
            OnPropertyChanged();
        }
    }

    public bool CanToggleStartup
    {
        get => canToggleStartup;
        private set
        {
            if (canToggleStartup == value)
            {
                return;
            }

            canToggleStartup = value;
            OnPropertyChanged();
        }
    }

    public bool IsStartupEnabled
    {
        get => isStartupEnabled;
        set
        {
            if (isStartupEnabled == value)
            {
                return;
            }

            _ = SetStartupEnabledAsync(value);
        }
    }

    public bool IsQuickSendEnabled
    {
        get => settings.Preferences.IsEnabled;
        set => UpdatePreferences(settings.Preferences with { IsEnabled = value });
    }

    public bool SaveSentCopy
    {
        get => settings.Preferences.SaveSentCopy;
        set => UpdatePreferences(settings.Preferences with { SaveSentCopy = value });
    }

    public bool SaveReceivedCopy
    {
        get => settings.Preferences.SaveReceivedCopy;
        set => UpdatePreferences(settings.Preferences with { SaveReceivedCopy = value });
    }

    public bool AllowsLocalSave
    {
        get => settings.Preferences.AllowsLocalSave;
        set => UpdatePreferences(settings.Preferences with { AllowsLocalSave = value });
    }

    public bool AutoDeleteAfter30Days
    {
        get => settings.Preferences.AutoDeleteAfter30Days;
        set
        {
            var updatedPreferences = settings.Preferences with { AutoDeleteAfter30Days = value };
            if (settings.Preferences == updatedPreferences)
            {
                return;
            }

            UpdatePreferences(updatedPreferences);
            if (value)
            {
                CleanupExpiredArchiveFiles();
            }
        }
    }

    public string ArchiveFolderStatus
    {
        get => archiveFolderStatus;
        private set
        {
            if (archiveFolderStatus == value)
            {
                return;
            }

            archiveFolderStatus = value;
            OnPropertyChanged();
        }
    }

    public void OpenRooms() => openRooms();

    public async Task SaveNicknameAsync(CancellationToken cancellationToken = default)
    {
        var normalized = NormalizeNickname(NicknameDraft);
        if (string.IsNullOrWhiteSpace(normalized))
        {
            NicknameStatus = "닉네임을 입력해 주세요.";
            return;
        }

        if (!CanSaveNickname)
        {
            return;
        }

        try
        {
            IsSavingNickname = true;
            NicknameStatus = "저장 중…";
            var savedNickname = await saveNickname(normalized, cancellationToken);
            var displayNickname = NormalizeNickname(savedNickname);
            Nickname = string.IsNullOrWhiteSpace(displayNickname) ? normalized : displayNickname;
            NicknameDraft = Nickname;
            NicknameStatus = "저장했어요.";
        }
        catch (OperationCanceledException)
        {
            NicknameStatus = "닉네임 저장을 취소했어요.";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException or ArgumentException or HttpRequestException)
        {
            NicknameStatus = "닉네임을 저장하지 못했어요. 다시 시도해 주세요.";
        }
        finally
        {
            IsSavingNickname = false;
        }
    }

    public async Task OpenArchiveFolderAsync()
    {
        try
        {
            ensureArchiveFolders();
            var opened = await openArchiveFolder(ArchiveRootPath);
            ArchiveFolderStatus = opened
                ? "저장 폴더를 열었어요."
                : "저장 폴더를 열지 못했어요.";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or InvalidOperationException)
        {
            ArchiveFolderStatus = "저장 폴더를 열지 못했어요.";
        }
    }

    public void SelectSection(SettingsSection section)
    {
        SelectedTabIndex = (int)section;
    }

    public void ApplyHotkey(HotkeySettingRow row)
    {
        HotkeyBinding binding;
        try
        {
            binding = row.ToBinding();
        }
        catch (InvalidOperationException ex)
        {
            row.StatusMessage = ex.Message;
            return;
        }

        var result = updateHotkey(row.Command, binding);
        if (result.Status != HotkeyRegistrationStatus.Success)
        {
            row.StatusMessage = result.Message;
            return;
        }

        hotkeys[row.Command] = binding;
        row.ApplyBinding(binding);
        row.StatusMessage = "저장했어요.";
        RefreshHotkeyLabels();
    }

    public async Task RefreshStartupAsync(CancellationToken cancellationToken = default)
    {
        var status = await startupTaskController.GetStatusAsync(cancellationToken);
        ApplyStartupStatus(status);
    }

    public void ApplySettings(ScreenFaceQuickSendSettings updatedSettings)
    {
        settings = updatedSettings;
        Devices.ApplyPreferences(updatedSettings.Devices);
        OnPropertyChanged(nameof(AutoPlayIncoming));
        OnPropertyChanged(nameof(NotificationSoundEnabled));
        OnPropertyChanged(nameof(AppearanceSelection));
        OnPropertyChanged(nameof(IsQuickSendEnabled));
        OnPropertyChanged(nameof(SaveSentCopy));
        OnPropertyChanged(nameof(SaveReceivedCopy));
        OnPropertyChanged(nameof(AllowsLocalSave));
        OnPropertyChanged(nameof(AutoDeleteAfter30Days));
    }

    public void ApplyProfileNickname(string updatedNickname)
    {
        var previousNickname = Nickname;
        var normalized = NormalizeNickname(updatedNickname);
        if (string.IsNullOrWhiteSpace(normalized))
        {
            return;
        }

        Nickname = normalized;
        if (!IsSavingNickname
            && string.Equals(NormalizeNickname(NicknameDraft), previousNickname, StringComparison.Ordinal))
        {
            NicknameDraft = normalized;
        }
        else
        {
            OnPropertyChanged(nameof(CanSaveNickname));
        }
    }

    private void UpdatePreferences(ScreenFaceQuickSendPreferences preferences)
    {
        if (settings.Preferences == preferences)
        {
            return;
        }

        settings = settings with { Preferences = preferences };
        saveSettings(settings);
        OnPropertyChanged(nameof(IsQuickSendEnabled));
        OnPropertyChanged(nameof(SaveSentCopy));
        OnPropertyChanged(nameof(SaveReceivedCopy));
        OnPropertyChanged(nameof(AllowsLocalSave));
        OnPropertyChanged(nameof(AutoDeleteAfter30Days));
    }

    private void CleanupExpiredArchiveFiles()
    {
        try
        {
            ensureArchiveFolders();
            deleteExpiredArchiveFiles();
            ArchiveFolderStatus = "30일이 지난 저장 영상을 정리했어요.";
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or InvalidOperationException)
        {
            ArchiveFolderStatus = "저장 영상을 정리하지 못했어요.";
        }
    }

    private async Task SetStartupEnabledAsync(bool isEnabled)
    {
        var status = await startupTaskController.SetEnabledAsync(isEnabled);
        ApplyStartupStatus(status);
    }

    private void ApplyStartupStatus(PingStartupTaskStatus status)
    {
        isStartupEnabled = status.IsEnabled;
        canToggleStartup = status.CanToggle;
        startupStatus = status.Message;
        OnPropertyChanged(nameof(IsStartupEnabled));
        OnPropertyChanged(nameof(CanToggleStartup));
        OnPropertyChanged(nameof(StartupStatus));
    }

    private static string LabelFor(string label, IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> hotkeys, HotkeyCommand command) =>
        hotkeys.TryGetValue(command, out var binding) ? $"{label}: {binding}" : $"{label}: 미지정";

    private static string QuickSendModeText(string action, IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> hotkeys) =>
        $"{HotkeyStatusText.BindingLabel(hotkeys, HotkeyCommand.QuickScreenFacePing)} {action}";

    private static string NormalizeNickname(string value) =>
        DisplayText.NormalizeWhitespace(value);

    private void RefreshHotkeyLabels()
    {
        FaceHotkey = LabelFor("얼굴 Ping", hotkeys, HotkeyCommand.FacePing);
        ScreenFaceHotkey = LabelFor("화면+얼굴 Ping", hotkeys, HotkeyCommand.ScreenFacePing);
        QuickSendHotkey = LabelFor("화면+얼굴 빠른 전송", hotkeys, HotkeyCommand.QuickScreenFacePing);
        HistoryHotkey = LabelFor("메신저", hotkeys, HotkeyCommand.History);
        QuickSendOffContent = QuickSendModeText("거울 열기", hotkeys);
        QuickSendOnContent = QuickSendModeText("바로 녹화", hotkeys);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

#if WINDOWS
public sealed partial class SettingsWindow : Window
{
    private readonly SettingsWindowViewModel viewModel;
    private readonly CancellationTokenSource deviceLifetime = new();
    private readonly DevicePairingPresenter pairing;

    public SettingsWindow(SettingsWindowViewModel viewModel)
    {
        this.viewModel = viewModel;
        InitializeComponent();
        Ping.Windows.App.UI.PingAppearance.Register(this);
        Ping.Windows.App.UI.WindowCaptureExclusion.Apply(this);
        Root.DataContext = viewModel;
        pairing = new(viewModel.Pairing, PairingImage);
        Closed += (_, _) => { pairing.Dispose(); viewModel.Updates.Dispose(); deviceLifetime.Cancel(); deviceLifetime.Dispose(); };
        Root.Loaded += (_, _) => { RefreshDevicesIfVisible(); _ = viewModel.Accounts.RefreshAsync(deviceLifetime.Token); };
        Ping.Windows.App.UI.SettingsWindowGeometry.Fit(this);
        _ = viewModel.RefreshStartupAsync();
    }

    public void RefreshSettings(ScreenFaceQuickSendSettings settings)
    {
        viewModel.ApplySettings(settings);
    }

    public void RefreshProfileNickname(string nickname)
    {
        viewModel.ApplyProfileNickname(nickname);
    }

    public void ShowSection(SettingsSection section)
    {
        viewModel.SelectSection(section);
    }

    private void SettingsTabs_SelectionChanged(object sender, Microsoft.UI.Xaml.Controls.SelectionChangedEventArgs args)
    {
        // ComboBox selection events also bubble through the settings tabs.
        if (args.AddedItems.Any(item => item is Microsoft.UI.Xaml.Controls.TabViewItem)
            || args.RemovedItems.Any(item => item is Microsoft.UI.Xaml.Controls.TabViewItem))
            RefreshDevicesIfVisible();
    }

    private void RefreshDevicesIfVisible()
    {
        var visible = SettingsTabs?.SelectedIndex == (int)SettingsSection.Devices;
        pairing?.SetVisible(visible);
        if (visible)
            _ = viewModel.Devices.RefreshAsync(deviceLifetime.Token);
    }
    public void ClearDevicePairing() => pairing.Clear();
    internal void ReportAccountTransitionFailure() => viewModel.Accounts.ReportTransitionFailure();
    internal void ReportUpdateFailure() => viewModel.Updates.ReportFailure();
    private async void CheckUpdateButton_Click(object sender, RoutedEventArgs args) => await viewModel.Updates.CheckAsync();
    private void CancelUpdateButton_Click(object sender, RoutedEventArgs args) => viewModel.Updates.Cancel();
    private async void InstallUpdateButton_Click(object sender, RoutedEventArgs args)
    {
        if (!viewModel.Updates.CanInstall) return;
        var dialog = new Microsoft.UI.Xaml.Controls.ContentDialog
        {
            XamlRoot = Root.XamlRoot, Title = "업데이트를 설치할까요?",
            Content = "패키지를 내려받아 확인한 후 진행 중인 촬영과 송수신을 종료하고 Ping을 다시 시작합니다. 계정·룸·설정은 유지됩니다.",
            PrimaryButtonText = "설치", CloseButtonText = "취소", DefaultButton = Microsoft.UI.Xaml.Controls.ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() == Microsoft.UI.Xaml.Controls.ContentDialogResult.Primary) await viewModel.Updates.InstallAsync();
    }
    private async void RefreshPairingButton_Click(object sender, RoutedEventArgs args) => await viewModel.Pairing.OpenAsync();

    private async void RefreshDeviceListButton_Click(object sender, RoutedEventArgs args)
        => await viewModel.Devices.RefreshAsync(deviceLifetime.Token);

    private void OpenRoomsButton_Click(object sender, RoutedEventArgs args)
    {
        viewModel.OpenRooms();
    }

    private async void SaveNicknameButton_Click(object sender, RoutedEventArgs args)
    {
        await viewModel.SaveNicknameAsync();
        if (!deviceLifetime.IsCancellationRequested) await viewModel.Accounts.RefreshAsync(deviceLifetime.Token);
    }

    private async void RefreshAccountsButton_Click(object sender, RoutedEventArgs args) => await viewModel.Accounts.RefreshAsync(deviceLifetime.Token);
    private async void SwitchAccountButton_Click(object sender, RoutedEventArgs args) => await viewModel.Accounts.SwitchAsync();
    private async void CreateAccountButton_Click(object sender, RoutedEventArgs args)
    {
        var dialog = new Microsoft.UI.Xaml.Controls.ContentDialog
        {
            XamlRoot = Root.XamlRoot, Title = "새 계정을 추가할까요?",
            Content = "현재 계정은 이 PC에 저장됩니다. 새 계정에서는 새 룸과 친구 연결을 시작합니다.",
            PrimaryButtonText = "추가", CloseButtonText = "취소", DefaultButton = Microsoft.UI.Xaml.Controls.ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() == Microsoft.UI.Xaml.Controls.ContentDialogResult.Primary) await viewModel.Accounts.CreateAsync();
    }
    private async void RemoveAccountButton_Click(object sender, RoutedEventArgs args)
    {
        if (!viewModel.Accounts.CanRemove) return;
        var dialog = new Microsoft.UI.Xaml.Controls.ContentDialog
        {
            XamlRoot = Root.XamlRoot, Title = "선택한 저장 계정을 삭제할까요?",
            Content = "이 PC의 저장 계정 목록에서 삭제합니다. 익명 계정은 이메일이나 비밀번호로 복구할 수 없어요. 다른 기기에 연결해 두지 않았다면 같은 계정으로 다시 연결하기 어려울 수 있습니다. 서버 계정과 다른 기기의 데이터는 삭제하지 않습니다.",
            PrimaryButtonText = "삭제", CloseButtonText = "취소", DefaultButton = Microsoft.UI.Xaml.Controls.ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() == Microsoft.UI.Xaml.Controls.ContentDialogResult.Primary) await viewModel.Accounts.RemoveAsync();
    }

    private async void OpenArchiveFolderButton_Click(object sender, RoutedEventArgs args)
    {
        await viewModel.OpenArchiveFolderAsync();
    }

    private void ApplyHotkeyButton_Click(object sender, RoutedEventArgs args)
    {
        if (sender is FrameworkElement { DataContext: HotkeySettingRow row })
        {
            viewModel.ApplyHotkey(row);
        }
    }
}
#endif
