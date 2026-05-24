using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.App.Hotkeys;

namespace Ping.Windows.App.Setup;

public sealed class HotkeySettingRow : INotifyPropertyChanged
{
    private static readonly string[] DefaultKeyChoices =
    [
        "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
        "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
    ];

    private bool isControl;
    private bool isAlt;
    private bool isShift;
    private bool isWindows;
    private string selectedKey;
    private string statusMessage = "Ready.";

    public HotkeySettingRow(HotkeyCommand command, string label, HotkeyBinding binding)
    {
        Command = command;
        Label = label;
        selectedKey = binding.Key;
        ApplyBinding(binding);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public HotkeyCommand Command { get; }

    public string Label { get; }

    public IReadOnlyList<string> KeyChoices => DefaultKeyChoices;

    public bool IsControl
    {
        get => isControl;
        set => SetField(ref isControl, value);
    }

    public bool IsAlt
    {
        get => isAlt;
        set => SetField(ref isAlt, value);
    }

    public bool IsShift
    {
        get => isShift;
        set => SetField(ref isShift, value);
    }

    public bool IsWindows
    {
        get => isWindows;
        set => SetField(ref isWindows, value);
    }

    public string SelectedKey
    {
        get => selectedKey;
        set
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return;
            }

            SetField(ref selectedKey, value.Trim().ToUpperInvariant());
        }
    }

    public string StatusMessage
    {
        get => statusMessage;
        set => SetField(ref statusMessage, value);
    }

    public HotkeyBinding ToBinding()
    {
        var modifiers = HotkeyModifiers.None;
        if (IsControl)
        {
            modifiers |= HotkeyModifiers.Control;
        }

        if (IsAlt)
        {
            modifiers |= HotkeyModifiers.Alt;
        }

        if (IsShift)
        {
            modifiers |= HotkeyModifiers.Shift;
        }

        if (IsWindows)
        {
            modifiers |= HotkeyModifiers.Windows;
        }

        if (modifiers == HotkeyModifiers.None)
        {
            throw new InvalidOperationException("Choose at least one modifier.");
        }

        var binding = HotkeyBinding.FromParts(modifiers, SelectedKey);
        _ = binding.ToVirtualKey();
        return binding;
    }

    public void ApplyBinding(HotkeyBinding binding)
    {
        isControl = binding.Modifiers.HasFlag(HotkeyModifiers.Control);
        isAlt = binding.Modifiers.HasFlag(HotkeyModifiers.Alt);
        isShift = binding.Modifiers.HasFlag(HotkeyModifiers.Shift);
        isWindows = binding.Modifiers.HasFlag(HotkeyModifiers.Windows);
        selectedKey = binding.Key;
        OnPropertyChanged(nameof(IsControl));
        OnPropertyChanged(nameof(IsAlt));
        OnPropertyChanged(nameof(IsShift));
        OnPropertyChanged(nameof(IsWindows));
        OnPropertyChanged(nameof(SelectedKey));
    }

    public static IReadOnlyList<HotkeySettingRow> FromBindings(
        IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> bindings) =>
        [
            FromBinding(bindings, HotkeyCommand.FacePing, "Face Ping"),
            FromBinding(bindings, HotkeyCommand.ScreenFacePing, "Screen+Face Ping"),
            FromBinding(bindings, HotkeyCommand.QuickScreenFacePing, "Quick Screen+Face Ping"),
            FromBinding(bindings, HotkeyCommand.History, "History")
        ];

    private static HotkeySettingRow FromBinding(
        IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> bindings,
        HotkeyCommand command,
        string label) =>
        new(
            command,
            label,
            bindings.TryGetValue(command, out var binding)
                ? binding
                : HotkeyBinding.Defaults()[command]);

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }

        field = value;
        OnPropertyChanged(propertyName);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
