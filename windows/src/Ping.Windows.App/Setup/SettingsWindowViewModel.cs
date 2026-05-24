using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.App.Capture;
using Ping.Windows.App.Hotkeys;

#if WINDOWS
using Microsoft.UI.Xaml;
#endif

namespace Ping.Windows.App.Setup;

public sealed class SettingsWindowViewModel : INotifyPropertyChanged
{
    private readonly Action<ScreenFaceQuickSendSettings> saveSettings;
    private readonly Action openRooms;
    private ScreenFaceQuickSendSettings settings;

    public SettingsWindowViewModel(
        string nickname,
        IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> hotkeys,
        ScreenFaceQuickSendSettings settings,
        Action<ScreenFaceQuickSendSettings> saveSettings,
        Action openRooms)
    {
        Nickname = nickname;
        FaceHotkey = LabelFor("Face Ping", hotkeys, HotkeyCommand.FacePing);
        ScreenFaceHotkey = LabelFor("Screen+Face Ping", hotkeys, HotkeyCommand.ScreenFacePing);
        QuickSendHotkey = LabelFor("Quick Screen+Face Ping", hotkeys, HotkeyCommand.QuickScreenFacePing);
        HistoryHotkey = LabelFor("History", hotkeys, HotkeyCommand.History);
        this.settings = settings;
        this.saveSettings = saveSettings;
        this.openRooms = openRooms;
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string Nickname { get; }

    public string FaceHotkey { get; }

    public string ScreenFaceHotkey { get; }

    public string QuickSendHotkey { get; }

    public string HistoryHotkey { get; }

    public string StartupStatus => "Packaged MSIX startup registration is configured in the release package step.";

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

    public bool AllowsLocalSave
    {
        get => settings.Preferences.AllowsLocalSave;
        set => UpdatePreferences(settings.Preferences with { AllowsLocalSave = value });
    }

    public void OpenRooms() => openRooms();

    public void ApplySettings(ScreenFaceQuickSendSettings updatedSettings)
    {
        settings = updatedSettings;
        OnPropertyChanged(nameof(IsQuickSendEnabled));
        OnPropertyChanged(nameof(SaveSentCopy));
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
        OnPropertyChanged(nameof(AllowsLocalSave));
    }

    private static string LabelFor(string label, IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> hotkeys, HotkeyCommand command) =>
        hotkeys.TryGetValue(command, out var binding) ? $"{label}: {binding}" : $"{label}: Unassigned";

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
    }

    public void RefreshSettings(ScreenFaceQuickSendSettings settings)
    {
        viewModel.ApplySettings(settings);
    }

    private void OpenRoomsButton_Click(object sender, RoutedEventArgs args)
    {
        viewModel.OpenRooms();
    }
}
#endif
