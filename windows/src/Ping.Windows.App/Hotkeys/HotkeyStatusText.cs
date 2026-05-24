namespace Ping.Windows.App.Hotkeys;

public static class HotkeyStatusText
{
    public static string Summary(IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> bindings) =>
        $"{BindingLabel(bindings, HotkeyCommand.FacePing)} face, "
        + $"{BindingLabel(bindings, HotkeyCommand.ScreenFacePing)} screen+face, "
        + $"{BindingLabel(bindings, HotkeyCommand.QuickScreenFacePing)} quick send, "
        + $"{BindingLabel(bindings, HotkeyCommand.History)} history";

    public static string RoomSummary(IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> bindings, int sendableRoomCount)
    {
        if (sendableRoomCount == 0)
        {
            return $"{BindingLabel(bindings, HotkeyCommand.FacePing)} ready, but no sendable room is available.";
        }

        return $"{BindingLabel(bindings, HotkeyCommand.FacePing)} face, "
            + $"{BindingLabel(bindings, HotkeyCommand.ScreenFacePing)} screen+face, "
            + $"and {BindingLabel(bindings, HotkeyCommand.QuickScreenFacePing)} quick send ready "
            + $"for {sendableRoomCount} room(s).";
    }

    public static string BindingLabel(
        IReadOnlyDictionary<HotkeyCommand, HotkeyBinding> bindings,
        HotkeyCommand command) =>
        bindings.TryGetValue(command, out var binding)
            ? binding.ToString()
            : HotkeyBinding.Defaults()[command].ToString();
}
