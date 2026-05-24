using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ping.Windows.App.Hotkeys;

public enum HotkeyCommand
{
    FacePing,
    ScreenFacePing,
    QuickScreenFacePing,
    History
}

[Flags]
public enum HotkeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Windows = 8
}

public sealed record HotkeyBinding(HotkeyModifiers Modifiers, string Key)
{
    public static HotkeyBinding Alt(string key) => FromParts(HotkeyModifiers.Alt, key);

    public static HotkeyBinding AltShift(string key) => FromParts(HotkeyModifiers.Alt | HotkeyModifiers.Shift, key);

    public static HotkeyBinding FromParts(HotkeyModifiers modifiers, string key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            throw new ArgumentException("A hotkey key is required.", nameof(key));
        }

        return new HotkeyBinding(modifiers, key.Trim().ToUpperInvariant());
    }

    public static IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> Defaults() => new Dictionary<HotkeyCommand, HotkeyBinding>
    {
        [HotkeyCommand.FacePing] = Alt("P"),
        [HotkeyCommand.ScreenFacePing] = Alt("L"),
        [HotkeyCommand.QuickScreenFacePing] = AltShift("L"),
        [HotkeyCommand.History] = Alt("O")
    };

    public uint ToModifierFlags()
    {
        const uint modAlt = 0x0001;
        const uint modControl = 0x0002;
        const uint modShift = 0x0004;
        const uint modWin = 0x0008;
        const uint modNoRepeat = 0x4000;

        uint flags = modNoRepeat;
        if (Modifiers.HasFlag(HotkeyModifiers.Alt))
        {
            flags |= modAlt;
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Control))
        {
            flags |= modControl;
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Shift))
        {
            flags |= modShift;
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Windows))
        {
            flags |= modWin;
        }

        return flags;
    }

    public uint ToVirtualKey()
    {
        if (Key.Length == 1)
        {
            var character = Key[0];
            if (character is >= 'A' and <= 'Z')
            {
                return character;
            }

            if (character is >= '0' and <= '9')
            {
                return character;
            }
        }

        if (Key.StartsWith('F') && int.TryParse(Key[1..], out var functionKey) && functionKey is >= 1 and <= 24)
        {
            return (uint)(0x70 + functionKey - 1);
        }

        throw new InvalidOperationException($"Unsupported hotkey key '{Key}'.");
    }

    public override string ToString()
    {
        var parts = new List<string>();
        if (Modifiers.HasFlag(HotkeyModifiers.Control))
        {
            parts.Add("Ctrl");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Alt))
        {
            parts.Add("Alt");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Shift))
        {
            parts.Add("Shift");
        }

        if (Modifiers.HasFlag(HotkeyModifiers.Windows))
        {
            parts.Add("Win");
        }

        parts.Add(Key);
        return string.Join("+", parts);
    }
}

public sealed class HotkeyPreferencesStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    private readonly string localAppDataRoot;

    public HotkeyPreferencesStore()
        : this(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData))
    {
    }

    public HotkeyPreferencesStore(string localAppDataRoot)
    {
        this.localAppDataRoot = localAppDataRoot;
    }

    public string PreferencesPath => Path.Combine(localAppDataRoot, "Ping", "UserPreferences.json");

    public IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> Load()
    {
        var defaults = HotkeyBinding.Defaults()
            .ToDictionary(pair => pair.Key, pair => pair.Value);

        if (!File.Exists(PreferencesPath))
        {
            return defaults;
        }

        UserPreferences? preferences;
        try
        {
            var json = File.ReadAllText(PreferencesPath);
            preferences = JsonSerializer.Deserialize<UserPreferences>(json, SerializerOptions);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return defaults;
        }

        if (preferences?.Hotkeys is null)
        {
            return defaults;
        }

        foreach (var pair in preferences.Hotkeys)
        {
            defaults[pair.Key] = pair.Value;
        }

        return defaults;
    }

    public void Save(IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> bindings)
    {
        var directory = Path.GetDirectoryName(PreferencesPath)
            ?? throw new InvalidOperationException("Could not resolve Ping preferences directory.");
        Directory.CreateDirectory(directory);

        var preferences = new UserPreferences(bindings.ToDictionary(pair => pair.Key, pair => pair.Value));
        var json = JsonSerializer.Serialize(preferences, SerializerOptions);
        File.WriteAllText(PreferencesPath, json);
    }

    private sealed record UserPreferences(Dictionary<HotkeyCommand, HotkeyBinding> Hotkeys);
}
