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
}
