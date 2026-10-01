namespace Ping.Windows.App.Setup;

public enum PingStartupTaskState
{
    Unavailable,
    Disabled,
    DisabledByUser,
    Enabled,
    DisabledByPolicy,
    EnabledByPolicy
}

public sealed record PingStartupTaskStatus(PingStartupTaskState State, string Message)
{
    public bool IsEnabled =>
        State is PingStartupTaskState.Enabled or PingStartupTaskState.EnabledByPolicy;

    public bool CanToggle =>
        State is PingStartupTaskState.Disabled or PingStartupTaskState.Enabled;
}

public interface IStartupTaskController
{
    Task<PingStartupTaskStatus> GetStatusAsync(CancellationToken cancellationToken = default);

    Task<PingStartupTaskStatus> SetEnabledAsync(bool isEnabled, CancellationToken cancellationToken = default);
}

public sealed class StartupTaskController : IStartupTaskController
{
    public const string TaskId = "PingWindowsStartup";

    public async Task<PingStartupTaskStatus> GetStatusAsync(CancellationToken cancellationToken = default)
    {
        if (!OperatingSystem.IsWindows())
        {
            return Unavailable();
        }

#if WINDOWS
        try
        {
            var task = await global::Windows.ApplicationModel.StartupTask.GetAsync(TaskId);
            cancellationToken.ThrowIfCancellationRequested();
            return ToStatus(task.State);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return new PingStartupTaskStatus(
                PingStartupTaskState.Unavailable,
                $"자동 시작 설정을 확인할 수 없어요: {ex.Message}");
        }
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return Unavailable();
#endif
    }

    public async Task<PingStartupTaskStatus> SetEnabledAsync(
        bool isEnabled,
        CancellationToken cancellationToken = default)
    {
        if (!OperatingSystem.IsWindows())
        {
            return Unavailable();
        }

#if WINDOWS
        try
        {
            var task = await global::Windows.ApplicationModel.StartupTask.GetAsync(TaskId);
            cancellationToken.ThrowIfCancellationRequested();
            if (isEnabled)
            {
                var enabledState = await task.RequestEnableAsync();
                cancellationToken.ThrowIfCancellationRequested();
                return ToStatus(enabledState);
            }

            task.Disable();
            return ToStatus(task.State);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return new PingStartupTaskStatus(
                PingStartupTaskState.Unavailable,
                $"자동 시작 설정을 확인할 수 없어요: {ex.Message}");
        }
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return Unavailable();
#endif
    }

    private static PingStartupTaskStatus Unavailable() =>
        new(
            PingStartupTaskState.Unavailable,
            "설치된 Ping에서 자동 시작을 설정할 수 있어요.");

#if WINDOWS
    private static PingStartupTaskStatus ToStatus(global::Windows.ApplicationModel.StartupTaskState state) =>
        state switch
        {
            global::Windows.ApplicationModel.StartupTaskState.Disabled => new(
                PingStartupTaskState.Disabled,
                "Windows 로그인 시 자동 시작하지 않습니다."),
            global::Windows.ApplicationModel.StartupTaskState.DisabledByUser => new(
                PingStartupTaskState.DisabledByUser,
                "Windows 설정에서 자동 시작이 꺼져 있습니다."),
            global::Windows.ApplicationModel.StartupTaskState.Enabled => new(
                PingStartupTaskState.Enabled,
                "Windows 로그인 시 자동 시작합니다."),
            global::Windows.ApplicationModel.StartupTaskState.DisabledByPolicy => new(
                PingStartupTaskState.DisabledByPolicy,
                "시스템 정책에 따라 자동 시작이 꺼져 있습니다."),
            global::Windows.ApplicationModel.StartupTaskState.EnabledByPolicy => new(
                PingStartupTaskState.EnabledByPolicy,
                "시스템 정책에 따라 자동 시작이 켜져 있습니다."),
            _ => new PingStartupTaskStatus(
                PingStartupTaskState.Unavailable,
                $"자동 시작 상태를 확인할 수 없어요: {state}.")
        };
#endif
}
