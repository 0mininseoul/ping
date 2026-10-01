using Ping.Windows.Core.Capture;
using Xunit;

namespace Ping.Windows.Core.Tests;

public sealed class CaptureMicrophoneSelectionTests
{
    [Fact]
    public void EndpointInstanceSelectsItsInterfaceWithoutTransformingEitherId()
    {
        var endpoint = new CaptureMicrophoneEndpoint("{opaque-endpoint-A}", @"SWD\MMDEVAPI\instance-A");
        var selected = CaptureMicrophoneDevice.Match(endpoint,
            [new("interface-B", "instance-B", true), new(@"\\?\audio#opaque-interface-A", endpoint.InstanceId, true)]);
        Assert.Equal(endpoint.EndpointId, selected.EndpointId);
        Assert.Equal(@"\\?\audio#opaque-interface-A", selected.WinRtId);
    }

    [Fact]
    public void MissingDisabledOrAmbiguousInterfaceNeverFallsBackToAnotherMicrophone()
    {
        var endpoint = new CaptureMicrophoneEndpoint("endpoint", "instance");
        Assert.Throws<InvalidOperationException>(() => CaptureMicrophoneDevice.Match(endpoint, [new("other", "other", true)]));
        Assert.Throws<InvalidOperationException>(() => CaptureMicrophoneDevice.Match(endpoint, [new("disabled", "instance", false)]));
        Assert.Throws<InvalidOperationException>(() => CaptureMicrophoneDevice.Match(endpoint,
            [new("one", "instance", true), new("two", "instance", true)]));
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("id\0other")]
    public void InvalidOpaqueIdsAreRejected(string id)
    {
        Assert.Throws<ArgumentException>(() => new CaptureMicrophoneDevice(id, "endpoint"));
        Assert.Throws<ArgumentException>(() => new CaptureMicrophoneDevice("interface", id));
        Assert.Throws<ArgumentException>(() => new CaptureMicrophoneEndpoint(id, "instance"));
        Assert.Throws<ArgumentException>(() => new CaptureMicrophoneEndpoint("endpoint", id));
    }

    [Fact]
    public async Task PreviewAndRecordingSharePairEvenIfSystemDefaultChanges()
    {
        var camera = new CameraOwnership();
        using (var lease = camera.TryAcquire(CameraPurpose.Manual)!)
        {
            var ready = new TaskCompletionSource<CaptureMicrophoneDevice>(TaskCreationOptions.RunContinuationsAsynchronously);
            var calls = 0;
            var preview = lease.MicrophoneSelection.GetAsync(_ => { calls++; return ready.Task; });
            var recording = lease.MicrophoneSelection.GetAsync(_ => throw new Exception("must reuse microphone"));
            var first = new CaptureMicrophoneDevice("interface-one", "endpoint-one");
            ready.SetResult(first);
            Assert.Same(first, await preview);
            Assert.Same(first, await recording);
            Assert.Equal(1, calls);
        }
        using var next = camera.TryAcquire(CameraPurpose.Manual)!;
        Assert.Equal("endpoint-two", (await next.MicrophoneSelection.GetAsync(_ =>
            Task.FromResult(new CaptureMicrophoneDevice("interface-two", "endpoint-two")))).EndpointId);
    }

    [Fact]
    public async Task CancellationWaitsForActualResolverAndClosedLeaseCannotReusePair()
    {
        var lease = new CameraOwnership().TryAcquire(CameraPurpose.Manual)!;
        using var cancellation = new CancellationTokenSource();
        var ready = new TaskCompletionSource<CaptureMicrophoneDevice>(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = lease.MicrophoneSelection.GetAsync(_ => ready.Task, cancellation.Token);
        cancellation.Cancel();
        Assert.False(pending.IsCompleted);
        ready.SetResult(new("interface", "endpoint"));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
        lease.Dispose();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => lease.MicrophoneSelection.GetAsync(_ =>
            throw new Exception("closed lease must not enumerate")));
    }
}
