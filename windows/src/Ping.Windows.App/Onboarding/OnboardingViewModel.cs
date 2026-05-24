using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Ping.Windows.App.Onboarding;

public enum OnboardingRowKind
{
    WindowsVersion,
    SupabaseConfig,
    ProcessPrivileges,
    Camera,
    Microphone,
    ScreenCapture,
    Notifications,
    Hotkeys,
    Startup
}

public enum OnboardingRowStatus
{
    Ready,
    Warning,
    Blocked,
    Unchecked
}

public enum OnboardingActionKind
{
    None,
    Retry,
    Settings,
    OpenFolder,
    Configure,
    Relaunch
}

public enum OnboardingProbeStatus
{
    Available,
    Blocked,
    Unchecked,
    Unsupported
}

public sealed record OnboardingAction(
    OnboardingActionKind Kind,
    string Label,
    string? Uri = null);

public sealed record OnboardingRowState(
    OnboardingRowKind Kind,
    string Title,
    OnboardingRowStatus Status,
    string Message,
    bool CanRetry,
    OnboardingAction? PrimaryAction = null,
    OnboardingAction? SecondaryAction = null)
{
    public bool HasPrimaryAction => PrimaryAction is not null;

    public string PrimaryActionLabel => PrimaryAction?.Label ?? string.Empty;
}

public sealed record OnboardingProbeState(
    OnboardingProbeStatus Status,
    string Message,
    string? SettingsUri = null,
    OnboardingActionKind? ActionKind = null,
    string? ActionLabel = null)
{
    public static OnboardingProbeState Available(string message = "Ready") =>
        new(OnboardingProbeStatus.Available, message);

    public static OnboardingProbeState Blocked(
        string message,
        string? settingsUri = null,
        OnboardingActionKind? actionKind = null,
        string? actionLabel = null) =>
        new(OnboardingProbeStatus.Blocked, message, settingsUri, actionKind, actionLabel);

    public static OnboardingProbeState Unchecked(string message) =>
        new(OnboardingProbeStatus.Unchecked, message);

    public static OnboardingProbeState Unsupported(string message) =>
        new(OnboardingProbeStatus.Unsupported, message);
}

public sealed record OnboardingEnvironmentState(
    WindowsSupportStatus WindowsStatus,
    bool IsSupabaseConfigured,
    bool IsElevated,
    OnboardingProbeState Camera,
    OnboardingProbeState Microphone,
    OnboardingProbeState ScreenCapture,
    OnboardingProbeState Notifications,
    OnboardingProbeState Hotkeys,
    OnboardingProbeState Startup)
{
    public static OnboardingEnvironmentState Initial() =>
        new(
            WindowsVersionProbe.CurrentStatus(),
            false,
            false,
            OnboardingProbeState.Unchecked("Camera has not been checked yet."),
            OnboardingProbeState.Unchecked("Microphone has not been checked yet."),
            OnboardingProbeState.Unchecked("Screen capture has not been checked yet."),
            OnboardingProbeState.Unchecked("Notifications have not been checked yet."),
            OnboardingProbeState.Unchecked("Hotkeys have not been checked yet."),
            OnboardingProbeState.Unchecked("Startup has not been checked yet."));

    public static OnboardingEnvironmentState Ready() =>
        new(
            WindowsSupportStatus.Supported,
            true,
            false,
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available(),
            OnboardingProbeState.Available());
}

public sealed class OnboardingViewModel : INotifyPropertyChanged
{
    private bool isScreenFaceQuickSendEnabled;
    private string screenFaceQuickSendStatusText = string.Empty;

    public OnboardingViewModel()
        : this(OnboardingEnvironmentState.Initial())
    {
    }

    public OnboardingViewModel(OnboardingEnvironmentState state)
    {
        Rows = new ObservableCollection<OnboardingRowState>();
        Apply(state);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<OnboardingRowState> Rows { get; }

    public bool IsScreenFaceQuickSendEnabled
    {
        get => isScreenFaceQuickSendEnabled;
        private set
        {
            if (isScreenFaceQuickSendEnabled == value)
            {
                return;
            }

            isScreenFaceQuickSendEnabled = value;
            OnPropertyChanged();
        }
    }

    public string ScreenFaceQuickSendStatusText
    {
        get => screenFaceQuickSendStatusText;
        private set
        {
            if (string.Equals(screenFaceQuickSendStatusText, value, StringComparison.Ordinal))
            {
                return;
            }

            screenFaceQuickSendStatusText = value;
            OnPropertyChanged();
        }
    }

    public void Apply(OnboardingEnvironmentState state)
    {
        var rows = BuildRows(state);
        Rows.Clear();
        foreach (var row in rows)
        {
            Rows.Add(row);
        }

        IsScreenFaceQuickSendEnabled =
            state.WindowsStatus == WindowsSupportStatus.Supported
            && state.IsSupabaseConfigured
            && state.Camera.Status == OnboardingProbeStatus.Available
            && state.Microphone.Status == OnboardingProbeStatus.Available
            && state.ScreenCapture.Status == OnboardingProbeStatus.Available
            && state.Hotkeys.Status == OnboardingProbeStatus.Available;
        ScreenFaceQuickSendStatusText = QuickSendStatusText(state, IsScreenFaceQuickSendEnabled);
    }

    public static IReadOnlyList<OnboardingRowState> BuildRows(OnboardingEnvironmentState state) =>
        [
            WindowsRow(state.WindowsStatus),
            SupabaseRow(state.IsSupabaseConfigured),
            ProcessPrivilegesRow(state.IsElevated),
            ProbeRow(OnboardingRowKind.Camera, "Camera", state.Camera),
            ProbeRow(OnboardingRowKind.Microphone, "Microphone", state.Microphone),
            ProbeRow(OnboardingRowKind.ScreenCapture, "Screen capture", state.ScreenCapture),
            ProbeRow(OnboardingRowKind.Notifications, "Notifications", state.Notifications),
            ProbeRow(OnboardingRowKind.Hotkeys, "Hotkeys", state.Hotkeys),
            ProbeRow(OnboardingRowKind.Startup, "Startup", state.Startup)
        ];

    private static OnboardingRowState WindowsRow(WindowsSupportStatus status) =>
        status switch
        {
            WindowsSupportStatus.Supported => new(
                OnboardingRowKind.WindowsVersion,
                "Windows version",
                OnboardingRowStatus.Ready,
                "Windows 11 24H2 or newer.",
                CanRetry: true),
            WindowsSupportStatus.UnsupportedWindows10 => new(
                OnboardingRowKind.WindowsVersion,
                "Windows version",
                OnboardingRowStatus.Warning,
                "Windows 10 is not a supported target for Ping Windows.",
                CanRetry: true),
            WindowsSupportStatus.UnsupportedOldWindows11 => new(
                OnboardingRowKind.WindowsVersion,
                "Windows version",
                OnboardingRowStatus.Warning,
                "Windows 11 24H2 or newer is required for full support.",
                CanRetry: true),
            _ => throw new ArgumentOutOfRangeException(nameof(status), status, null)
        };

    private static OnboardingRowState ProcessPrivilegesRow(bool isElevated)
    {
        if (!isElevated)
        {
            return new(
                OnboardingRowKind.ProcessPrivileges,
                "Process privileges",
                OnboardingRowStatus.Ready,
                "Ping is running as a normal user process.",
                CanRetry: true);
        }

        return new(
            OnboardingRowKind.ProcessPrivileges,
            "Process privileges",
            OnboardingRowStatus.Blocked,
            "Ping is running as administrator. Windows app notifications are unavailable while elevated.",
            CanRetry: true,
            PrimaryAction: new OnboardingAction(OnboardingActionKind.Relaunch, "Restart normally"));
    }

    private static OnboardingRowState SupabaseRow(bool configured)
    {
        if (configured)
        {
            return new(
                OnboardingRowKind.SupabaseConfig,
                "Supabase config",
                OnboardingRowStatus.Ready,
                "Supabase.json is present.",
                CanRetry: true);
        }

        return new(
            OnboardingRowKind.SupabaseConfig,
            "Supabase config",
            OnboardingRowStatus.Blocked,
            "Missing or invalid Supabase.json in the Ping local config folder.",
            CanRetry: true,
            PrimaryAction: new OnboardingAction(OnboardingActionKind.OpenFolder, "Open config folder"));
    }

    private static OnboardingRowState ProbeRow(
        OnboardingRowKind kind,
        string title,
        OnboardingProbeState probe) =>
        probe.Status switch
        {
            OnboardingProbeStatus.Available => new(
                kind,
                title,
                OnboardingRowStatus.Ready,
                probe.Message,
                CanRetry: true),
            OnboardingProbeStatus.Blocked => new(
                kind,
                title,
                OnboardingRowStatus.Blocked,
                probe.Message,
                CanRetry: true,
                PrimaryAction: PrimaryActionFor(probe)),
            OnboardingProbeStatus.Unchecked => new(
                kind,
                title,
                OnboardingRowStatus.Unchecked,
                probe.Message,
                CanRetry: true,
                PrimaryAction: new OnboardingAction(OnboardingActionKind.Retry, "Check again")),
            OnboardingProbeStatus.Unsupported => new(
                kind,
                title,
                OnboardingRowStatus.Warning,
                probe.Message,
                CanRetry: false,
                PrimaryAction: PrimaryActionFor(probe)),
            _ => throw new ArgumentOutOfRangeException(nameof(probe), probe.Status, null)
        };

    private static OnboardingAction? PrimaryActionFor(OnboardingProbeState probe)
    {
        if (!string.IsNullOrWhiteSpace(probe.SettingsUri))
        {
            return new OnboardingAction(OnboardingActionKind.Settings, "Open settings", probe.SettingsUri);
        }

        if (probe.ActionKind is { } kind && kind != OnboardingActionKind.None)
        {
            return new OnboardingAction(kind, probe.ActionLabel ?? DefaultLabel(kind));
        }

        return null;
    }

    private static string DefaultLabel(OnboardingActionKind kind) =>
        kind switch
        {
            OnboardingActionKind.Retry => "Check again",
            OnboardingActionKind.Settings => "Open settings",
            OnboardingActionKind.OpenFolder => "Open folder",
            OnboardingActionKind.Configure => "Configure",
            OnboardingActionKind.Relaunch => "Relaunch",
            _ => "Open"
        };

    private static string QuickSendStatusText(OnboardingEnvironmentState state, bool isEnabled)
    {
        if (isEnabled)
        {
            return "Screen+face quick send is ready for Alt+Shift+L.";
        }

        var blocker = QuickSendBlocker(state);
        return $"Screen+face quick send is disabled until {blocker} is ready.";
    }

    private static string QuickSendBlocker(OnboardingEnvironmentState state)
    {
        if (state.WindowsStatus != WindowsSupportStatus.Supported)
        {
            return "Windows 11 24H2+";
        }

        if (!state.IsSupabaseConfigured)
        {
            return "Supabase config";
        }

        if (state.Camera.Status != OnboardingProbeStatus.Available)
        {
            return "camera access";
        }

        if (state.Microphone.Status != OnboardingProbeStatus.Available)
        {
            return "microphone access";
        }

        if (state.ScreenCapture.Status != OnboardingProbeStatus.Available)
        {
            return "screen capture";
        }

        if (state.Hotkeys.Status != OnboardingProbeStatus.Available)
        {
            return "hotkeys";
        }

        return "required checks";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
