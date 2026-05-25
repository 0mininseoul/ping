using System.Text.Json.Serialization;

namespace Ping.Windows.Core.Models;

public sealed record MirrorPosition(
    [property: JsonPropertyName("xRatio")] double XRatio,
    [property: JsonPropertyName("yRatio")] double YRatio);
