using System.Text.Json;

namespace Ping.Windows.App.UI;

public sealed class MessengerWindowPlacementStore(string path)
{
    public MessengerPlacement? Load()
    {
        try
        {
            if (!File.Exists(path) || new FileInfo(path).Length > 8192) return null;
            var state = JsonSerializer.Deserialize<PlacementState>(File.ReadAllText(path));
            return state is { Version: 1, Placement: { } value } && Valid(value) ? value : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return null; }
    }

    public bool Save(MessengerPlacement placement)
    {
        if (!Valid(placement)) return false;
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
            File.WriteAllText(temporary, JsonSerializer.Serialize(new PlacementState(1, placement)));
            File.Move(temporary, path, overwrite: true);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return false; }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
    }

    private static bool Valid(MessengerPlacement value) => !string.IsNullOrWhiteSpace(value.DeviceName) && value.DeviceName.Length <= 128
        && double.IsFinite(value.XRatio) && double.IsFinite(value.YRatio)
        && double.IsFinite(value.WidthDips) && value.WidthDips > 0 && double.IsFinite(value.HeightDips) && value.HeightDips > 0;
    private sealed record PlacementState(int Version, MessengerPlacement? Placement);
}
