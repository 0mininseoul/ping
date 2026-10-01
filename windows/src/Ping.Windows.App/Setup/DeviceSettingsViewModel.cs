using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ping.Windows.App.Capture;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Setup;

public sealed class DeviceSettingsViewModel : INotifyPropertyChanged
{
    private readonly Func<CancellationToken, Task<CaptureDeviceCatalog>> read;
    private readonly Action<CaptureDevicePreferences> save;
    private CaptureDevicePreferences preferences;
    private CaptureDeviceCatalog catalog = new([], []);
    private bool updating, isLoading;
    private CameraChoice? selectedCamera;
    private MicrophoneChoice? selectedMicrophone;
    private string status = "목록 새로고침으로 연결된 기기를 확인할 수 있어요.";

    public DeviceSettingsViewModel(CaptureDevicePreferences preferences, Action<CaptureDevicePreferences> save,
        Func<CancellationToken, Task<CaptureDeviceCatalog>>? read = null)
    {
        this.preferences = preferences; this.save = save;
#if WINDOWS
        this.read = read ?? WindowsCaptureDeviceCatalog.ReadAsync;
#else
        this.read = read ?? (_ => Task.FromResult(new CaptureDeviceCatalog([], [])));
#endif
        UpdateChoices();
    }
    public event PropertyChangedEventHandler? PropertyChanged;
    public IReadOnlyList<CameraChoice> Cameras { get; private set; } = [];
    public IReadOnlyList<MicrophoneChoice> Microphones { get; private set; } = [];
    public bool IsLoading { get => isLoading; private set { isLoading = value; Notify(); Notify(nameof(CanRefresh)); } }
    public bool CanRefresh => !IsLoading;
    public string Status { get => status; private set { status = value; Notify(); } }
    public CameraChoice? SelectedCamera
    {
        get => selectedCamera;
        set
        {
            if (value is null || selectedCamera == value) return;
            selectedCamera = value; Notify();
            if (updating) return;
            preferences = preferences with { CameraId = value.Id }; save(preferences);
        }
    }
    public MicrophoneChoice? SelectedMicrophone
    {
        get => selectedMicrophone;
        set
        {
            if (value is null || selectedMicrophone == value) return;
            selectedMicrophone = value; Notify();
            if (updating) return;
            preferences = preferences with { Microphone = value.Device }; save(preferences);
        }
    }
    public void ApplyPreferences(CaptureDevicePreferences value) { preferences = value; UpdateChoices(); }
    public async Task RefreshAsync(CancellationToken token = default)
    {
        if (IsLoading) return;
        IsLoading = true; Status = "연결된 기기를 확인하고 있어요…";
        try
        {
            catalog = await read(token); token.ThrowIfCancellationRequested(); UpdateChoices();
            Status = catalog.Warning ?? (catalog.Cameras.Count == 0 || catalog.Microphones.Count == 0
                ? "사용할 카메라 또는 마이크가 없어요. 연결 후 목록을 새로고침해 주세요."
                : "선택한 기기는 다음 촬영부터 적용됩니다.");
        }
        catch (OperationCanceledException) { }
        catch (Exception error) when (error is InvalidOperationException or UnauthorizedAccessException or System.Runtime.InteropServices.COMException)
        { Status = "기기 목록을 읽지 못했어요. 연결과 Windows 카메라·마이크 권한을 확인해 주세요."; }
        finally { IsLoading = false; }
    }
    private void UpdateChoices()
    {
        updating = true;
        try
        {
            var cameras = new List<CameraChoice> { new(null, "기본 카메라") }; cameras.AddRange(catalog.Cameras);
            var microphones = new List<MicrophoneChoice> { new(null, "Windows 기본 통신 마이크") }; microphones.AddRange(catalog.Microphones);
            if (preferences.CameraId is { } id && !cameras.Any(item => item.Id == id)) cameras.Add(new(id, "연결 안됨 · 선택한 카메라"));
            if (preferences.Microphone is { } mic && !microphones.Any(item => item.Device == mic)) microphones.Add(new(mic, "연결 안됨 · 선택한 마이크"));
            Cameras = cameras; Microphones = microphones; Notify(nameof(Cameras)); Notify(nameof(Microphones));
            selectedCamera = cameras.Single(item => item.Id == preferences.CameraId);
            selectedMicrophone = microphones.Single(item => item.Device == preferences.Microphone);
            Notify(nameof(SelectedCamera)); Notify(nameof(SelectedMicrophone));
        }
        finally { updating = false; }
    }
    private void Notify([CallerMemberName] string? property = null) => PropertyChanged?.Invoke(this, new(property));
}
