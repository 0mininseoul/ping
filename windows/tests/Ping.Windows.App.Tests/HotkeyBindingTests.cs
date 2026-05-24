using Ping.Windows.App.Hotkeys;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class HotkeyBindingTests
{
    [Fact]
    public void Default_bindings_match_windows_parity_contract()
    {
        var defaults = HotkeyBinding.Defaults();

        Assert.Equal(HotkeyBinding.Alt("P"), defaults[HotkeyCommand.FacePing]);
        Assert.Equal(HotkeyBinding.Alt("L"), defaults[HotkeyCommand.ScreenFacePing]);
        Assert.Equal(HotkeyBinding.AltShift("L"), defaults[HotkeyCommand.QuickScreenFacePing]);
        Assert.Equal(HotkeyBinding.Alt("O"), defaults[HotkeyCommand.History]);
    }

    [Fact]
    public void Register_reports_conflict_from_registrar()
    {
        using var registrar = new FakeHotkeyRegistrar { ConflictOnRegister = true };
        using var manager = new GlobalHotkeyManager(registrar);

        var result = manager.Register(HotkeyCommand.FacePing, HotkeyBinding.Alt("P"));

        Assert.Equal(HotkeyRegistrationStatus.Conflict, result.Status);
        Assert.Equal(HotkeyCommand.FacePing, result.Command);
        Assert.Contains("already", result.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Dispose_releases_registered_hotkeys_on_shutdown()
    {
        using var registrar = new FakeHotkeyRegistrar();
        using var manager = new GlobalHotkeyManager(registrar);

        Assert.Equal(
            HotkeyRegistrationStatus.Success,
            manager.Register(HotkeyCommand.FacePing, HotkeyBinding.Alt("P")).Status);
        Assert.Equal(
            HotkeyRegistrationStatus.Success,
            manager.Register(HotkeyCommand.History, HotkeyBinding.Alt("O")).Status);

        manager.Dispose();

        Assert.Equal(2, registrar.UnregisteredIds.Count);
        Assert.Empty(registrar.RegisteredIds);
    }

    [Fact]
    public void Preferences_round_trip_under_local_app_data_shape()
    {
        var root = Path.Combine(Path.GetTempPath(), "PingHotkeyTests", Guid.NewGuid().ToString("N"));
        var store = new HotkeyPreferencesStore(root);
        var changed = HotkeyBinding.Defaults()
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        changed[HotkeyCommand.FacePing] = HotkeyBinding.FromParts(HotkeyModifiers.Alt | HotkeyModifiers.Shift, "F");

        try
        {
            store.Save(changed);

            var loaded = store.Load();

            Assert.Equal(changed[HotkeyCommand.FacePing], loaded[HotkeyCommand.FacePing]);
            Assert.Equal(changed[HotkeyCommand.ScreenFacePing], loaded[HotkeyCommand.ScreenFacePing]);
            Assert.EndsWith(Path.Combine("Ping", "UserPreferences.json"), store.PreferencesPath);
            Assert.True(File.Exists(store.PreferencesPath));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    private sealed class FakeHotkeyRegistrar : IHotkeyRegistrar
    {
        public bool ConflictOnRegister { get; init; }
        public HashSet<int> RegisteredIds { get; } = [];
        public List<int> UnregisteredIds { get; } = [];

        public event EventHandler<int>? HotkeyPressed
        {
            add { }
            remove { }
        }

        public HotkeyRegistrarResult Register(int id, HotkeyBinding binding)
        {
            if (ConflictOnRegister)
            {
                return HotkeyRegistrarResult.Conflict("Hotkey is already registered by another app.");
            }

            RegisteredIds.Add(id);
            return HotkeyRegistrarResult.Success();
        }

        public void Unregister(int id)
        {
            RegisteredIds.Remove(id);
            UnregisteredIds.Add(id);
        }

        public void Dispose()
        {
        }
    }
}
