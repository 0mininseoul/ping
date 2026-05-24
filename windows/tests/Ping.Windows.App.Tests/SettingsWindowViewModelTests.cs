using Ping.Windows.App.Capture;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Setup;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class SettingsWindowViewModelTests
{
    [Fact]
    public void StorageTogglesPersistThroughSettingsCallback()
    {
        ScreenFaceQuickSendSettings? saved = null;
        var viewModel = new SettingsWindowViewModel(
            "Youngmin",
            HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default,
            settings => saved = settings,
            () => { });

        viewModel.SaveSentCopy = true;
        viewModel.SaveReceivedCopy = false;
        viewModel.AllowsLocalSave = true;

        var finalSettings = saved ?? throw new InvalidOperationException("Settings were not saved.");
        Assert.True(finalSettings.Preferences.SaveSentCopy);
        Assert.False(finalSettings.Preferences.SaveReceivedCopy);
        Assert.True(finalSettings.Preferences.AllowsLocalSave);
    }

    [Fact]
    public void OpenRoomsInvokesConfiguredAction()
    {
        var opened = false;
        var viewModel = new SettingsWindowViewModel(
            "Youngmin",
            HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default,
            _ => { },
            () => opened = true);

        viewModel.OpenRooms();

        Assert.True(opened);
    }

    [Fact]
    public void SettingsSectionSelectionCanOpenHotkeysDirectly()
    {
        var viewModel = new SettingsWindowViewModel(
            "Youngmin",
            HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default,
            _ => { },
            () => { },
            initialSection: SettingsSection.Hotkeys);

        Assert.Equal((int)SettingsSection.Hotkeys, viewModel.SelectedTabIndex);

        viewModel.SelectSection(SettingsSection.Storage);

        Assert.Equal((int)SettingsSection.Storage, viewModel.SelectedTabIndex);
    }

    [Fact]
    public void ApplyingHotkeyPersistsThroughCallbackAndRefreshesLabels()
    {
        var savedCommand = HotkeyCommand.History;
        var savedBinding = HotkeyBinding.Alt("O");
        var viewModel = new SettingsWindowViewModel(
            "Youngmin",
            HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default,
            _ => { },
            () => { },
            updateHotkey: (command, binding) =>
            {
                savedCommand = command;
                savedBinding = binding;
                return HotkeyRegistrationResult.Success(command, binding);
            });
        var row = Assert.Single(viewModel.HotkeyRows, row => row.Command == HotkeyCommand.FacePing);

        row.IsControl = true;
        row.IsAlt = true;
        row.IsShift = false;
        row.SelectedKey = "F";
        viewModel.ApplyHotkey(row);

        Assert.Equal(HotkeyCommand.FacePing, savedCommand);
        Assert.Equal(HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Alt, "F"), savedBinding);
        Assert.Equal("Saved.", row.StatusMessage);
        Assert.Equal("Face Ping: Ctrl+Alt+F", viewModel.FaceHotkey);
    }

    [Fact]
    public void ApplyingConflictingHotkeyDoesNotReplaceLabel()
    {
        var viewModel = new SettingsWindowViewModel(
            "Youngmin",
            HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default,
            _ => { },
            () => { },
            updateHotkey: (command, binding) => HotkeyRegistrationResult.Conflict(
                command,
                binding,
                "Hotkey is already registered by another app."));
        var row = Assert.Single(viewModel.HotkeyRows, row => row.Command == HotkeyCommand.FacePing);

        row.IsAlt = true;
        row.SelectedKey = "F";
        viewModel.ApplyHotkey(row);

        Assert.Equal("Hotkey is already registered by another app.", row.StatusMessage);
        Assert.Equal("Face Ping: Alt+P", viewModel.FaceHotkey);
    }

    [Fact]
    public void ApplyingQuickSendHotkeyRefreshesQuickSendModeCopy()
    {
        var viewModel = new SettingsWindowViewModel(
            "Youngmin",
            HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default,
            _ => { },
            () => { },
            updateHotkey: (command, binding) => HotkeyRegistrationResult.Success(command, binding));
        var row = Assert.Single(viewModel.HotkeyRows, row => row.Command == HotkeyCommand.QuickScreenFacePing);

        row.IsControl = true;
        row.IsAlt = true;
        row.IsShift = true;
        row.SelectedKey = "Q";
        viewModel.ApplyHotkey(row);

        Assert.Equal("Quick Screen+Face Ping: Ctrl+Alt+Shift+Q", viewModel.QuickSendHotkey);
        Assert.Equal("Ctrl+Alt+Shift+Q opens mirror", viewModel.QuickSendOffContent);
        Assert.Equal("Ctrl+Alt+Shift+Q records immediately", viewModel.QuickSendOnContent);
    }

    [Fact]
    public void ApplyingHotkeyRequiresModifier()
    {
        var viewModel = new SettingsWindowViewModel(
            "Youngmin",
            HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default,
            _ => { },
            () => { });
        var row = Assert.Single(viewModel.HotkeyRows, row => row.Command == HotkeyCommand.History);

        row.IsAlt = false;
        row.IsControl = false;
        row.IsShift = false;
        row.IsWindows = false;
        viewModel.ApplyHotkey(row);

        Assert.Equal("Choose at least one modifier.", row.StatusMessage);
        Assert.Equal("History: Alt+O", viewModel.HistoryHotkey);
    }

    [Fact]
    public async Task StartupToggleUsesStartupTaskController()
    {
        var startup = new RecordingStartupTaskController(new PingStartupTaskStatus(
            PingStartupTaskState.Disabled,
            "Ping will not start with Windows."));
        var viewModel = new SettingsWindowViewModel(
            "Youngmin",
            HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default,
            _ => { },
            () => { },
            startup);

        await viewModel.RefreshStartupAsync();
        Assert.False(viewModel.IsStartupEnabled);
        Assert.True(viewModel.CanToggleStartup);

        viewModel.IsStartupEnabled = true;
        await startup.LastSetTask;

        Assert.True(viewModel.IsStartupEnabled);
        Assert.True(startup.LastRequestedState);
        Assert.Equal("Ping starts with Windows.", viewModel.StartupStatus);
    }

    private sealed class RecordingStartupTaskController(PingStartupTaskStatus initialStatus) : IStartupTaskController
    {
        private readonly TaskCompletionSource<PingStartupTaskStatus> lastSet = new();
        private PingStartupTaskStatus status = initialStatus;

        public bool LastRequestedState { get; private set; }

        public Task<PingStartupTaskStatus> LastSetTask => lastSet.Task;

        public Task<PingStartupTaskStatus> GetStatusAsync(CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            return Task.FromResult(status);
        }

        public Task<PingStartupTaskStatus> SetEnabledAsync(bool isEnabled, CancellationToken cancellationToken = default)
        {
            _ = cancellationToken;
            LastRequestedState = isEnabled;
            status = new PingStartupTaskStatus(
                isEnabled ? PingStartupTaskState.Enabled : PingStartupTaskState.Disabled,
                isEnabled ? "Ping starts with Windows." : "Ping will not start with Windows.");
            lastSet.SetResult(status);
            return Task.FromResult(status);
        }
    }
}
