using System.Text;
using Ping.Windows.App.Capture;
using Xunit;

namespace Ping.Windows.App.Tests;

public sealed class NativeMicrophoneIdentityReaderTests
{
    [Fact]
    public async Task ReadsBothOpaqueIdsWithoutActivatingMicrophone()
    {
        var api = new Api();
        var result = await new NativeMicrophoneIdentityReader(api).ReadAsync(default);
        Assert.Equal("{endpoint-fixture}", result.EndpointId);
        Assert.Equal(@"SWD\MMDEVAPI\instance-fixture", result.InstanceId);
        Assert.Equal(1, api.Calls);
    }

    [Fact]
    public async Task CancelDuringNativeEnumerationWaitsForItsActualReturn()
    {
        var api = new Api { Block = true };
        using var cancellation = new CancellationTokenSource();
        var pending = new NativeMicrophoneIdentityReader(api).ReadAsync(cancellation.Token);
        await api.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        cancellation.Cancel();
        try { Assert.False(pending.IsCompleted); }
        finally { api.Finish.Set(); }
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => pending);
    }

    [Theory]
    [InlineData(PingCaptureErrorCode.NoMicrophone, typeof(InvalidOperationException))]
    [InlineData(PingCaptureErrorCode.AccessDenied, typeof(UnauthorizedAccessException))]
    public async Task NativeErrorCannotCreateAFallbackIdentity(PingCaptureErrorCode code, Type type)
    {
        var api = new Api { Result = (int)code };
        Assert.IsType(type, await Record.ExceptionAsync(() => new NativeMicrophoneIdentityReader(api).ReadAsync(default)));
    }

    [Fact]
    public async Task PreCancelledRequestNeverStartsNativeEnumeration()
    {
        var api = new Api();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => new NativeMicrophoneIdentityReader(api).ReadAsync(new(true)));
        Assert.Equal(0, api.Calls);
    }

    private sealed class Api : INativeMicrophoneIdentityApi
    {
        public bool Block;
        public int Calls, Result;
        public TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public ManualResetEventSlim Finish = new();
        public int Read(StringBuilder endpoint, int endpointCapacity, StringBuilder instance, int instanceCapacity)
        {
            Interlocked.Increment(ref Calls); Started.SetResult();
            if (Block && !Finish.Wait(TimeSpan.FromSeconds(3))) throw new TimeoutException("Fixture resolver was not released.");
            endpoint.Append("{endpoint-fixture}"); instance.Append(@"SWD\MMDEVAPI\instance-fixture");
            return Result;
        }
    }
}
