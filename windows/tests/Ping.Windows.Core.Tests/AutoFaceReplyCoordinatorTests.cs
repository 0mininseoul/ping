using Ping.Windows.Core.Backend;
using Ping.Windows.Core.Capture;
using Ping.Windows.Core.Incoming;
using Ping.Windows.Core.Models;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class AutoFaceReplyCoordinatorTests
{
    [Fact]
    public async Task FreshArrivalRecordsThreeSecondsAndAlwaysReleasesResources()
    {
        await using var fixture = new Fixture();
        Assert.Equal(AutoFaceReplyDecision.Record, fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live));
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.Equal(TimeSpan.FromSeconds(3), fixture.Duration);
        Assert.Equal(1, fixture.Sends);
        Assert.Equal("peer", fixture.Input!.OriginalMessage.SenderUid);
        Assert.Equal("me", fixture.Input.SenderUid);
        Assert.True(fixture.Input.AllowsLocalSave);
        Assert.Equal(new[] { "reply.mp4" }, fixture.Deleted);
        Assert.Equal(1, fixture.IndicatorDisposals);
        Assert.False(fixture.Camera.IsBusy);
    }

    [Fact]
    public async Task DuplicateAndConcurrentArrivalsDoNotQueueCameraWork()
    {
        await using var fixture = new Fixture();
        var recording = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Record = (_, token) => recording.Task.WaitAsync(token);
        Assert.Equal(AutoFaceReplyDecision.Record, fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live));
        Assert.Equal(AutoFaceReplyDecision.AlreadyReplied, fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live));
        Assert.Equal(AutoFaceReplyDecision.CameraBusy, fixture.Coordinator.HandleIncoming(Video("next"), IncomingArrivalSource.Live));
        recording.SetResult("reply.mp4");
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.Equal(AutoFaceReplyDecision.AlreadyReplied, fixture.Coordinator.HandleIncoming(Video("next"), IncomingArrivalSource.Live));
        Assert.Equal(1, fixture.Sends);
    }

    [Fact]
    public async Task BusyManualCameraNeverCausesDeferredSurpriseCapture()
    {
        await using var fixture = new Fixture();
        using var manual = fixture.Camera.TryAcquire(CameraPurpose.Manual)!;
        Assert.Equal(AutoFaceReplyDecision.CameraBusy, fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live));
        manual.Dispose();
        Assert.Equal(AutoFaceReplyDecision.AlreadyReplied, fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live));
        Assert.Equal(0, fixture.Recordings);
    }

    [Fact]
    public async Task PlaybackAndCatchupSourcesCannotActivateCamera()
    {
        await using var fixture = new Fixture();
        foreach (var source in new[] { IncomingArrivalSource.StartupCatchUp, IncomingArrivalSource.ReconnectCatchUp,
            IncomingArrivalSource.NotificationClick, IncomingArrivalSource.HistoryReplay })
            Assert.Equal(AutoFaceReplyDecision.NotLive, fixture.Coordinator.HandleIncoming(Video(), source));
        Assert.Equal(AutoFaceReplyDecision.AutoReplyMessage, fixture.Coordinator.HandleIncoming(Video() with { IsAutoReply = true }, IncomingArrivalSource.Live));
        Assert.Equal(0, fixture.Recordings);
    }

    [Fact]
    public async Task CatchupNotificationRetryCannotReclassifySameVideoAsLive()
    {
        await using var fixture = new Fixture();
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.ReconnectCatchUp);
        Assert.Equal(AutoFaceReplyDecision.AlreadyReplied, fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live));
        Assert.Equal(0, fixture.Recordings);
    }

    [Fact]
    public async Task UncooperativeCaptureReturningAfterSleepIsDeletedWithoutSend()
    {
        await using var fixture = new Fixture();
        var recording = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Record = (_, _) => recording.Task;
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live);
        fixture.Activity.SetDisplayAwake(false);
        fixture.Activity.SetDisplayAwake(true);
        recording.SetResult("late.mp4");
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.Equal(0, fixture.Sends);
        Assert.Equal(new[] { "late.mp4" }, fixture.Deleted);
        Assert.False(fixture.Camera.IsBusy);
    }

    [Fact]
    public async Task StopAfterDisposalIsIdempotent()
    {
        var fixture = new Fixture();
        await fixture.DisposeAsync();
        await fixture.Coordinator.StopAsync();
        await fixture.DisposeAsync();
    }

    [Fact]
    public async Task SleepCancelsInitializationAndCannotResumeRecordingLater()
    {
        await using var fixture = new Fixture();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Record = async (_, token) => { started.SetResult(); await Task.Delay(Timeout.InfiniteTimeSpan, token); return "never.mp4"; };
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live);
        await started.Task;
        fixture.Activity.SetDisplayAwake(false);
        fixture.Activity.SetDisplayAwake(true);
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.Equal(0, fixture.Sends);
        Assert.False(fixture.Camera.IsBusy);
        Assert.Equal(1, fixture.IndicatorDisposals);
        Assert.Equal(AutoFaceReplyDecision.AlreadyReplied, fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live));
    }

    [Fact]
    public async Task DisplaySleepDuringIndicatorAbandonsBeforeCameraInitialization()
    {
        await using var fixture = new Fixture();
        fixture.BeforeIndicator = () => fixture.Activity.SetSuspended(true);
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live);
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.Equal(0, fixture.Recordings);
        Assert.Equal(0, fixture.Sends);
        Assert.Equal(1, fixture.IndicatorDisposals);
    }

    [Fact]
    public async Task SlowRecordingAndAccountChangeCannotSendOldClip()
    {
        await using var fixture = new Fixture();
        fixture.Record = (_, _) => { fixture.Now = fixture.Now.AddSeconds(61); return Task.FromResult("reply.mp4"); };
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live);
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.Equal(0, fixture.Sends);
        Assert.Single(fixture.Deleted);

        fixture.Now = AutoFaceReplyPolicyTests.Now;
        fixture.Record = (_, _) => { fixture.Identity = new("another", "Another", false); return Task.FromResult("reply.mp4"); };
        fixture.Coordinator.HandleIncoming(Video("different"), IncomingArrivalSource.Live);
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.Equal(0, fixture.Sends);
        Assert.Equal(2, fixture.Deleted.Count);
    }

    [Fact]
    public async Task SleepDuringUploadCancelsAndFinalGuardRemainsFalseAfterResume()
    {
        await using var fixture = new Fixture();
        var uploading = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Func<bool>? guard = null;
        fixture.Send = async (_, canSend, token) =>
        {
            guard = canSend;
            uploading.SetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, token);
            return true;
        };
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live);
        await uploading.Task;
        fixture.Activity.SetLocked(true);
        fixture.Activity.SetLocked(false);
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.False(guard!());
        Assert.Equal(1, fixture.IndicatorDisposals);
        Assert.Single(fixture.Deleted);
        Assert.False(fixture.Camera.IsBusy);
    }

    [Fact]
    public async Task UserCapturePreemptsAndCleanupFinishesBeforeManualLease()
    {
        await using var fixture = new Fixture();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var finishCleanup = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Record = async (_, token) =>
        {
            started.SetResult();
            try { await Task.Delay(Timeout.InfiniteTimeSpan, token); }
            finally { await finishCleanup.Task; }
            return "never.mp4";
        };
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live);
        await started.Task;
        var userGrant = fixture.Camera.AcquireManualAsync();
        Assert.False(userGrant.IsCompleted);
        finishCleanup.SetResult();
        using var manual = await userGrant;
        Assert.NotNull(manual);
        Assert.Equal(1, fixture.IndicatorDisposals);
        Assert.Equal(0, fixture.Sends);
    }

    [Fact]
    public async Task CaptureFailureIsObservedAndNeverRetriedForSameArrival()
    {
        await using var fixture = new Fixture();
        fixture.Record = (_, _) => Task.FromException<string>(new IOException("device unavailable"));
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live);
        await fixture.Coordinator.WaitForIdleAsync();
        Assert.Single(fixture.Errors);
        Assert.Equal(1, fixture.IndicatorDisposals);
        Assert.False(fixture.Camera.IsBusy);
        Assert.Equal(AutoFaceReplyDecision.AlreadyReplied, fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live));
    }

    [Fact]
    public async Task StopAwaitsOwnedCaptureAndPreventsFurtherArrivals()
    {
        await using var fixture = new Fixture();
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Record = async (_, token) => { started.SetResult(); await Task.Delay(Timeout.InfiniteTimeSpan, token); return "never.mp4"; };
        fixture.Coordinator.HandleIncoming(Video(), IncomingArrivalSource.Live);
        await started.Task;
        await fixture.Coordinator.StopAsync();
        Assert.False(fixture.Camera.IsBusy);
        Assert.Equal(1, fixture.IndicatorDisposals);
        Assert.NotEqual(AutoFaceReplyDecision.Record, fixture.Coordinator.HandleIncoming(Video("after-stop"), IncomingArrivalSource.Live));
    }

    private static VideoMessage Video(string id = "original") => AutoFaceReplyPolicyTests.Video(id);

    private sealed class Fixture : IAsyncDisposable
    {
        public CameraOwnership Camera { get; } = new();
        public CaptureActivityState Activity { get; } = new();
        public AutoReplyIdentity? Identity = new("me", "Me", true);
        public DateTimeOffset Now = AutoFaceReplyPolicyTests.Now;
        public TimeSpan Duration;
        public int Recordings, Sends, IndicatorDisposals;
        public AutoReplyVideoInput? Input;
        public List<string> Deleted = [];
        public List<Exception> Errors = [];
        public Func<TimeSpan, CancellationToken, Task<string>> Record = (_, _) => Task.FromResult("reply.mp4");
        public Func<AutoReplyVideoInput, Func<bool>, CancellationToken, Task<bool>> Send = (_, guard, _) => Task.FromResult(guard());
        public Action? BeforeIndicator;
        public AutoFaceReplyCoordinator Coordinator { get; }

        public Fixture()
        {
            Coordinator = new(Camera, Activity, AutoFaceReplyPolicyTests.Started, () => Identity, () => true,
                async (lease, duration, token) => { Assert.Equal(CameraPurpose.AutomaticReply, lease.Purpose); Duration = duration; ++Recordings; return await Record(duration, token); },
                (message, token) => { BeforeIndicator?.Invoke(); return Task.FromResult<IAsyncDisposable>(new Indicator(this)); },
                async (input, guard, token) => { ++Sends; Input = input; return await Send(input, guard, token); },
                path => Deleted.Add(path), () => Now, error => Errors.Add(error));
        }
        public ValueTask DisposeAsync() => Coordinator.DisposeAsync();
        private sealed class Indicator(Fixture owner) : IAsyncDisposable
        {
            public ValueTask DisposeAsync() { ++owner.IndicatorDisposals; return ValueTask.CompletedTask; }
        }
    }
}
