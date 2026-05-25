using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Models;

[JsonConverter(typeof(CaptureModeJsonConverter))]
public enum CaptureMode
{
    FaceOnly,
    ScreenFace
}

public static class CaptureModeWire
{
    public static string ToWireValue(this CaptureMode mode) => mode switch
    {
        CaptureMode.FaceOnly => "face_only",
        CaptureMode.ScreenFace => "screen_face",
        _ => throw new ArgumentOutOfRangeException(nameof(mode), mode, "Unknown capture mode.")
    };

    public static CaptureMode Parse(string value) => value switch
    {
        "face_only" => CaptureMode.FaceOnly,
        "screen_face" => CaptureMode.ScreenFace,
        _ => throw new JsonException($"Unknown capture mode wire value: {value}")
    };
}

public sealed class CaptureModeJsonConverter : JsonConverter<CaptureMode>
{
    public override CaptureMode Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.GetString() ?? throw new JsonException("Capture mode cannot be null.");
        return CaptureModeWire.Parse(value);
    }

    public override void Write(Utf8JsonWriter writer, CaptureMode value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.ToWireValue());
    }
}
