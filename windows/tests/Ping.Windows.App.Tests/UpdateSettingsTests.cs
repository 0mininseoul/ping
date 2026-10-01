using Ping.Windows.App.Setup;
using Ping.Windows.Core.Updates;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class UpdateSettingsTests
{
    [Fact]
    public async Task CheckEnablesInstallOnlyForNewReleaseAndRetryClearsFailure()
    {
        var fail = true;
        var model = new UpdateSettingsViewModel("0.3.46.0", _ => fail ? throw new IOException("private detail") : Task.FromResult<WindowsUpdateCandidate?>(
            new(new(0, 3, 80, 0), "x64", new("https://0minping.vercel.app/downloads/windows/Ping-Windows-v0.3.80-x64.msix"))), (_, _, _) => Task.CompletedTask);
        await model.CheckAsync(); Assert.False(model.CanInstall); Assert.DoesNotContain("private", model.Status);
        fail = false; await model.CheckAsync(); Assert.True(model.CanInstall); Assert.Contains("0.3.80", model.Status);
    }
    [Fact]
    public async Task InstallDisablesDuplicateCallsAndCancelReleasesUiForRetry()
    {
        var model = new UpdateSettingsViewModel("0.3.46.0", _ => Task.FromResult<WindowsUpdateCandidate?>(
            new(new(0, 3, 80, 0), "x64", new("https://0minping.vercel.app/downloads/windows/Ping-Windows-v0.3.80-x64.msix"))),
            async (_, _, token) => await Task.Delay(Timeout.InfiniteTimeSpan, token));
        await model.CheckAsync(); var installing = model.InstallAsync();
        Assert.False(model.CanInstall); Assert.False(model.CanCheck); Assert.True(model.CanCancel);
        await model.InstallAsync(); model.Cancel(); await installing;
        Assert.True(model.CanInstall); Assert.True(model.CanCheck); Assert.Contains("취소", model.Status);
    }
}
