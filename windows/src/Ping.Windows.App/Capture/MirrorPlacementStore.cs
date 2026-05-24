using System.Text.Json;
using Ping.Windows.Core.Models;

namespace Ping.Windows.App.Capture;

public sealed class MirrorPlacementStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private static readonly MirrorPosition DefaultPosition = new(0.5, 0.5);
    private readonly string path;

    public MirrorPlacementStore()
        : this(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Ping",
            "MirrorPlacement.json"))
    {
    }

    public MirrorPlacementStore(string path)
    {
        this.path = path;
    }

    public MirrorPosition Load(CaptureMode mode)
    {
        var state = LoadState();
        return Normalize(mode switch
        {
            CaptureMode.FaceOnly => state.FaceOnly,
            CaptureMode.ScreenFace => state.ScreenFace,
            _ => null
        });
    }

    public void Save(CaptureMode mode, MirrorPosition position)
    {
        var state = LoadState();
        var normalized = Normalize(position);
        state = mode switch
        {
            CaptureMode.FaceOnly => state with { FaceOnly = normalized },
            CaptureMode.ScreenFace => state with { ScreenFace = normalized },
            _ => state
        };

        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(path, JsonSerializer.Serialize(state, JsonOptions));
    }

    private MirrorPlacementState LoadState()
    {
        try
        {
            if (!File.Exists(path))
            {
                return new MirrorPlacementState();
            }

            return JsonSerializer.Deserialize<MirrorPlacementState>(
                    File.ReadAllText(path),
                    JsonOptions)
                ?? new MirrorPlacementState();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException)
        {
            return new MirrorPlacementState();
        }
    }

    private static MirrorPosition Normalize(MirrorPosition? position)
    {
        if (position is null)
        {
            return DefaultPosition;
        }

        return new MirrorPosition(
            NormalizeRatio(position.XRatio),
            NormalizeRatio(position.YRatio));
    }

    private static double NormalizeRatio(double value)
    {
        if (!double.IsFinite(value))
        {
            return 0.5;
        }

        return Math.Max(0, Math.Min(1, value));
    }

    private sealed record MirrorPlacementState
    {
        public MirrorPosition? FaceOnly { get; init; }

        public MirrorPosition? ScreenFace { get; init; }
    }
}
