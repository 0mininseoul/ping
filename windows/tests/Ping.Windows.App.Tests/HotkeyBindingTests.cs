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
    public void Failed_rebind_keeps_existing_hotkey_registered()
    {
        using var registrar = new FakeHotkeyRegistrar();
        using var manager = new GlobalHotkeyManager(registrar);

        var first = manager.Register(HotkeyCommand.FacePing, HotkeyBinding.Alt("P"));
        registrar.ConflictOnRegister = true;
        var second = manager.Register(HotkeyCommand.FacePing, HotkeyBinding.AltShift("P"));

        Assert.Equal(HotkeyRegistrationStatus.Success, first.Status);
        Assert.Equal(HotkeyRegistrationStatus.Conflict, second.Status);
        Assert.Single(registrar.RegisteredIds);
        Assert.Empty(registrar.UnregisteredIds);
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

    [Fact]
    public void Corrupt_preferences_fall_back_to_default_hotkeys()
    {
        var root = Path.Combine(Path.GetTempPath(), "PingHotkeyTests", Guid.NewGuid().ToString("N"));
        var store = new HotkeyPreferencesStore(root);

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(store.PreferencesPath)!);
            File.WriteAllText(store.PreferencesPath, "{not-json");

            var loaded = store.Load();

            Assert.Equal(HotkeyBinding.Defaults()[HotkeyCommand.FacePing], loaded[HotkeyCommand.FacePing]);
            Assert.Equal(HotkeyBinding.Defaults()[HotkeyCommand.QuickScreenFacePing], loaded[HotkeyCommand.QuickScreenFacePing]);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void Invalid_hotkey_values_fall_back_per_command()
    {
        var root = Path.Combine(Path.GetTempPath(), "PingHotkeyTests", Guid.NewGuid().ToString("N"));
        var store = new HotkeyPreferencesStore(root);

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(store.PreferencesPath)!);
            File.WriteAllText(
                store.PreferencesPath,
                """
                {
                  "hotkeys": {
                    "facePing": { "modifiers": 1, "key": "Slash" },
                    "screenFacePing": { "modifiers": 3, "key": "S" },
                    "quickScreenFacePing": { "modifiers": 16, "key": "Q" },
                    "history": { "modifiers": 0, "key": "O" }
                  }
                }
                """);

            var loaded = store.Load();

            Assert.Equal(HotkeyBinding.Defaults()[HotkeyCommand.FacePing], loaded[HotkeyCommand.FacePing]);
            Assert.Equal(
                HotkeyBinding.FromParts(HotkeyModifiers.Alt | HotkeyModifiers.Control, "S"),
                loaded[HotkeyCommand.ScreenFacePing]);
            Assert.Equal(HotkeyBinding.Defaults()[HotkeyCommand.QuickScreenFacePing], loaded[HotkeyCommand.QuickScreenFacePing]);
            Assert.Equal(HotkeyBinding.Defaults()[HotkeyCommand.History], loaded[HotkeyCommand.History]);
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void Unknown_hotkey_commands_are_ignored_without_dropping_valid_preferences()
    {
        var root = Path.Combine(Path.GetTempPath(), "PingHotkeyTests", Guid.NewGuid().ToString("N"));
        var store = new HotkeyPreferencesStore(root);
        var changed = HotkeyBinding.Defaults()
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        changed[HotkeyCommand.FacePing] = HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Alt, "F");
        changed[(HotkeyCommand)999] = HotkeyBinding.Alt("Z");

        try
        {
            store.Save(changed);

            var loaded = store.Load();

            Assert.Equal(
                HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Alt, "F"),
                loaded[HotkeyCommand.FacePing]);
            Assert.False(loaded.ContainsKey((HotkeyCommand)999));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void Status_text_uses_customized_hotkey_bindings()
    {
        var bindings = HotkeyBinding.Defaults()
            .ToDictionary(pair => pair.Key, pair => pair.Value);
        bindings[HotkeyCommand.FacePing] = HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Shift, "F");
        bindings[HotkeyCommand.ScreenFacePing] = HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Alt, "S");
        bindings[HotkeyCommand.QuickScreenFacePing] = HotkeyBinding.FromParts(HotkeyModifiers.Control | HotkeyModifiers.Alt | HotkeyModifiers.Shift, "Q");

        var summary = HotkeyStatusText.Summary(bindings);
        var emptyRoomSummary = HotkeyStatusText.RoomSummary(bindings, sendableRoomCount: 0);
        var readyRoomSummary = HotkeyStatusText.RoomSummary(bindings, sendableRoomCount: 2);

        Assert.Equal("Ctrl+Shift+F face, Ctrl+Alt+S screen+face, Ctrl+Alt+Shift+Q quick send, Alt+O history", summary);
        Assert.Equal("Ctrl+Alt+Shift+Q", HotkeyStatusText.BindingLabel(bindings, HotkeyCommand.QuickScreenFacePing));
        Assert.Equal("Ctrl+Shift+F ready, but no sendable room is available.", emptyRoomSummary);
        Assert.Equal("Ctrl+Shift+F face, Ctrl+Alt+S screen+face, and Ctrl+Alt+Shift+Q quick send ready for 2 room(s).", readyRoomSummary);
    }

    private sealed class FakeHotkeyRegistrar : IHotkeyRegistrar
    {
        public bool ConflictOnRegister { get; set; }
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
