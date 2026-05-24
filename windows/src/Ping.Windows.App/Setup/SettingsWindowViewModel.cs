using System.ComponentModel;
using System.Collections.ObjectModel;
using System.Runtime.CompilerServices;
using Ping.Windows.App.Capture;
using Ping.Windows.App.Hotkeys;

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
    Info = 4
}

public sealed class SettingsWindowViewModel : INotifyPropertyChanged
{
    private readonly Action<ScreenFaceQuickSendSettings> saveSettings;
    private readonly Action openRooms;
    private readonly IStartupTaskController startupTaskController;
    private readonly Func<HotkeyCommand, HotkeyBinding, HotkeyRegistrationResult> updateHotkey;
    private readonly Dictionary<HotkeyCommand, HotkeyBinding> hotkeys;
    private ScreenFaceQuickSendSettings settings;
    private bool isStartupEnabled;
    private bool canToggleStartup;
    private string startupStatus = "Checking startup registration...";
    private string faceHotkey;
    private string screenFaceHotkey;
    private string quickSendHotkey;
    private string historyHotkey;
    private string quickSendOffContent;
    private string quickSendOnContent;
    private int selectedTabIndex;

    public SettingsWindowViewModel(
        string nickname,
        IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> hotkeys,
        ScreenFaceQuickSendSettings settings,
        Action<ScreenFaceQuickSendSettings> saveSettings,
        Action openRooms,
        IStartupTaskController? startupTaskController = null,
        Func<HotkeyCommand, HotkeyBinding, HotkeyRegistrationResult>? updateHotkey = null,
        SettingsSection initialSection = SettingsSection.General)
    {
        Nickname = nickname;
        selectedTabIndex = (int)initialSection;
        this.hotkeys = hotkeys.ToDictionary(pair => pair.Key, pair => pair.Value);
        this.settings = settings;
        this.saveSettings = saveSettings;
        this.openRooms = openRooms;
        this.startupTaskController = startupTaskController ?? new StartupTaskController();
        this.updateHotkey = updateHotkey ?? ((command, binding) => HotkeyRegistrationResult.Success(command, binding));
        faceHotkey = LabelFor("Face Ping", this.hotkeys, HotkeyCommand.FacePing);
        screenFaceHotkey = LabelFor("Screen+Face Ping", this.hotkeys, HotkeyCommand.ScreenFacePing);
        quickSendHotkey = LabelFor("Quick Screen+Face Ping", this.hotkeys, HotkeyCommand.QuickScreenFacePing);
        historyHotkey = LabelFor("History", this.hotkeys, HotkeyCommand.History);
        quickSendOffContent = QuickSendModeText("opens mirror", this.hotkeys);
        quickSendOnContent = QuickSendModeText("records immediately", this.hotkeys);
        HotkeyRows = new ObservableCollection<HotkeySettingRow>(
            HotkeySettingRow.FromBindings(this.hotkeys));
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Nickname { get; }

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

    public void OpenRooms() => openRooms();

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
        row.StatusMessage = "Saved.";
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
        OnPropertyChanged(nameof(IsQuickSendEnabled));
        OnPropertyChanged(nameof(SaveSentCopy));
        OnPropertyChanged(nameof(SaveReceivedCopy));
        OnPropertyChanged(nameof(AllowsLocalSave));
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
        hotkeys.TryGetValue(command, out var binding) ? $"{label}: {binding}" : $"{label}: Unassigned";

    private static string QuickSendModeText(string action, IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> hotkeys) =>
        $"{HotkeyStatusText.BindingLabel(hotkeys, HotkeyCommand.QuickScreenFacePing)} {action}";

    private void RefreshHotkeyLabels()
    {
        FaceHotkey = LabelFor("Face Ping", hotkeys, HotkeyCommand.FacePing);
        ScreenFaceHotkey = LabelFor("Screen+Face Ping", hotkeys, HotkeyCommand.ScreenFacePing);
        QuickSendHotkey = LabelFor("Quick Screen+Face Ping", hotkeys, HotkeyCommand.QuickScreenFacePing);
        HistoryHotkey = LabelFor("History", hotkeys, HotkeyCommand.History);
        QuickSendOffContent = QuickSendModeText("opens mirror", hotkeys);
        QuickSendOnContent = QuickSendModeText("records immediately", hotkeys);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

#if WINDOWS
public sealed partial class SettingsWindow : Window
{
    private readonly SettingsWindowViewModel viewModel;

    public SettingsWindow(SettingsWindowViewModel viewModel)
    {
        this.viewModel = viewModel;
        InitializeComponent();
        Root.DataContext = viewModel;
        _ = viewModel.RefreshStartupAsync();
    }

    public void RefreshSettings(ScreenFaceQuickSendSettings settings)
    {
        viewModel.ApplySettings(settings);
    }

    public void ShowSection(SettingsSection section)
    {
        viewModel.SelectSection(section);
    }

    private void OpenRoomsButton_Click(object sender, RoutedEventArgs args)
    {
        viewModel.OpenRooms();
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
