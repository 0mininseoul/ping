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
        viewModel.AllowsLocalSave = true;

        var finalSettings = saved ?? throw new InvalidOperationException("Settings were not saved.");
        Assert.True(finalSettings.Preferences.SaveSentCopy);
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
