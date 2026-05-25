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
                $"Startup registration is unavailable: {ex.Message}");
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
                $"Startup registration is unavailable: {ex.Message}");
        }
#else
        await Task.CompletedTask.ConfigureAwait(false);
        return Unavailable();
#endif
    }

    private static PingStartupTaskStatus Unavailable() =>
        new(
            PingStartupTaskState.Unavailable,
            "Startup registration is available only in packaged Windows builds.");

#if WINDOWS
    private static PingStartupTaskStatus ToStatus(global::Windows.ApplicationModel.StartupTaskState state) =>
        state switch
        {
            global::Windows.ApplicationModel.StartupTaskState.Disabled => new(
                PingStartupTaskState.Disabled,
                "Ping will not start with Windows."),
            global::Windows.ApplicationModel.StartupTaskState.DisabledByUser => new(
                PingStartupTaskState.DisabledByUser,
                "Startup was disabled in Windows Settings."),
            global::Windows.ApplicationModel.StartupTaskState.Enabled => new(
                PingStartupTaskState.Enabled,
                "Ping starts with Windows."),
            global::Windows.ApplicationModel.StartupTaskState.DisabledByPolicy => new(
                PingStartupTaskState.DisabledByPolicy,
                "Startup is disabled by system policy."),
            global::Windows.ApplicationModel.StartupTaskState.EnabledByPolicy => new(
                PingStartupTaskState.EnabledByPolicy,
                "Startup is enabled by system policy."),
            _ => new PingStartupTaskStatus(
                PingStartupTaskState.Unavailable,
                $"Startup returned an unknown state: {state}.")
        };
#endif
}
