using Ping.Windows.App.Capture;
using Ping.Windows.App.Hotkeys;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class DeviceSettingsTests
{
    [Fact]
    public async Task ActualDeviceSelectionPersistsBothOpaqueIdsAndKeepsOtherSettings()
    {
        ScreenFaceQuickSendSettings? saved = null;
        var microphone = new CaptureMicrophoneDevice("winrt-mic", "endpoint-mic");
        var model = new SettingsWindowViewModel("나", HotkeyBinding.Defaults(),
            ScreenFaceQuickSendSettings.Default with { DefaultRoomId = "room", NotificationSoundEnabled = false },
            value => saved = value, () => { }, deviceCatalog: _ => Task.FromResult(new CaptureDeviceCatalog(
                [new("camera", "카메라")], [new(microphone, "마이크")])));
        await model.Devices.RefreshAsync();
        Assert.Null(saved);
        model.Devices.SelectedCamera = model.Devices.Cameras[1];
        model.Devices.SelectedMicrophone = model.Devices.Microphones[1];
        Assert.Equal("camera", saved!.Devices.CameraId);
        Assert.Equal(microphone, saved.Devices.Microphone);
        Assert.Equal("room", saved.DefaultRoomId);
        Assert.False(saved.NotificationSoundEnabled);
    }
    [Fact]
    public async Task DisconnectedSelectionIsVisibleAndNeverSilentlyChangedToDefault()
    {
        var selected = new CaptureDevicePreferences("missing", new("missing-winrt", "missing-endpoint"));
        var saves = 0;
        var model = new DeviceSettingsViewModel(selected, _ => saves++, _ => Task.FromResult(new CaptureDeviceCatalog([], [])));
        await model.RefreshAsync();
        Assert.Equal("missing", model.SelectedCamera!.Id);
        Assert.Contains("연결 안됨", model.SelectedCamera.Label);
        Assert.Equal(selected.Microphone, model.SelectedMicrophone!.Device);
        Assert.Equal(0, saves);
        Assert.False(model.IsLoading);
    }
    [Fact]
    public async Task NativeCatalogReadsAllIdentityPairsWithoutDeviceActivation()
    {
        var devices = await new NativeMicrophoneCatalogReader(new Catalog()).ReadAsync(default);
        Assert.Equal(2, devices.Count);
        Assert.Equal("endpoint-2", devices[1].EndpointId);
        Assert.Equal("instance-2", devices[1].InstanceId);
    }
    private sealed class Catalog : INativeMicrophoneCatalogApi
    {
        public int Enumerate(Action<string, string> found)
        { found("endpoint-1", "instance-1"); found("endpoint-2", "instance-2"); return 0; }
    }
}
