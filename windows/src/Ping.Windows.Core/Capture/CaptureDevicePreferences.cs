namespace Ping.Windows.Core.Capture;

public sealed record CaptureDevicePreferences(string? CameraId = null, CaptureMicrophoneDevice? Microphone = null);
