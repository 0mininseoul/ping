#if PING_UI_SMOKE
using System.Reflection;
using System.Text.Json;
using Microsoft.Windows.AppLifecycle;

namespace Ping.Windows.App.Diagnostics;

internal static class ActivationHandoffSmoke
{
    internal static int Run(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var checks = new List<string>();
        var lost = 0;
        var lateQueued = 0;
        const int iterations = 20_000;
        EventHandler<AppActivationArguments>? handler = null;
        try
        {
            var arguments = AppInstance.GetCurrent().GetActivatedEventArgs();
            var publish = typeof(Program).GetMethod("OnActivated", BindingFlags.NonPublic | BindingFlags.Static)!
                .CreateDelegate<EventHandler<AppActivationArguments>>();
            Program.TakePendingActivations();
            publish(null, arguments);
            if (Program.TakePendingActivations().Count != 1) throw new InvalidOperationException("Initial activation was not retained.");
            checks.Add("activation before application construction is retained");

            var received = 0;
            handler = (_, _) => Interlocked.Increment(ref received);
            var activationGate = typeof(Program).GetField("ActivationLock", BindingFlags.NonPublic | BindingFlags.Static)!.GetValue(null)!;
            using var started = new ManualResetEventSlim();
            var delayedPublisher = new Thread(() => { started.Set(); publish(null, arguments); });
            int drainedAtRegistration;
            lock (activationGate)
            {
                delayedPublisher.Start();
                if (!started.Wait(TimeSpan.FromSeconds(10)) || !SpinWait.SpinUntil(
                        () => (delayedPublisher.ThreadState & ThreadState.WaitSleepJoin) != 0, TimeSpan.FromSeconds(10)))
                    throw new TimeoutException("Publisher did not reach the retained-activation gate.");
                Program.Activated += handler;
                drainedAtRegistration = Program.TakePendingActivations().Count;
            }
            if (!delayedPublisher.Join(TimeSpan.FromSeconds(10))) throw new TimeoutException("Publisher did not finish.");
            lateQueued = Program.TakePendingActivations().Count;
            Program.Activated -= handler;
            if (received + drainedAtRegistration != 1 || lateQueued != 0)
            {
                lost++;
                throw new InvalidOperationException($"Activation arriving during handler registration was stranded: delivered={received}; initial={drainedAtRegistration}; late={lateQueued}.");
            }
            checks.Add("activation paused at startup handoff reaches newly registered handler without a late queued item");
            using var rendezvous = new Barrier(2);
            void Meet()
            {
                if (!rendezvous.SignalAndWait(TimeSpan.FromSeconds(10))) throw new TimeoutException("Activation race rendezvous timed out.");
            }
            var producer = Task.Factory.StartNew(() =>
            {
                for (var index = 0; index < iterations; index++)
                {
                    Meet();
                    publish(null, arguments);
                    Meet();
                }
            }, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            for (var index = 0; index < iterations; index++)
            {
                received = 0;
                Meet();
                Program.Activated += handler;
                var initialQueue = Program.TakePendingActivations();
                Meet();
                var unclaimed = Program.TakePendingActivations();
                Program.Activated -= handler;
                if (received + initialQueue.Count != 1) lost++;
                lateQueued += unclaimed.Count;
            }
            producer.GetAwaiter().GetResult();
            if (lost != 0 || lateQueued != 0)
                throw new InvalidOperationException($"Startup activation lost after handler registration: {lost}; queued too late: {lateQueued}.");
            checks.Add($"all {iterations} concurrent startup handoffs deliver exactly once without stranded activations");

            received = 0;
            Program.Activated += handler;
            Parallel.For(0, 1_000, _ => publish(null, arguments));
            Program.Activated -= handler;
            if (received != 1_000 || Program.TakePendingActivations().Count != 0)
                throw new InvalidOperationException("Warm activations were lost or queued twice.");
            checks.Add("1000 concurrent warm activations reach the registered handler exactly once");
            Write(true, null);
            return 0;
        }
        catch (Exception error)
        {
            Write(false, error.GetType().Name + ": " + error.Message);
            return 1;
        }
        finally
        {
            if (handler is not null) Program.Activated -= handler;
            Program.TakePendingActivations();
        }
        void Write(bool success, string? error) => File.WriteAllText(Path.Combine(outputDirectory, "result.json"),
            JsonSerializer.Serialize(new { Success = success, Checks = checks, Iterations = iterations,
                Lost = lost, LateQueued = lateQueued, Error = error, ShellToastClickTested = false, UserAccountAccessed = false }));
    }
}
#endif
