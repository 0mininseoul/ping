using System.Net.NetworkInformation;
using Microsoft.Windows.System.Power;
using Ping.Windows.Core.Backend;

namespace Ping.Windows.App.Bootstrap;

public sealed class ConnectionLifecycleAdapter : IDisposable
{
    private readonly ConnectionSupervisor supervisor;
    private bool powerRegistered;

    public ConnectionLifecycleAdapter(ConnectionSupervisor supervisor)
    {
        this.supervisor = supervisor;
        NetworkChange.NetworkAvailabilityChanged += HandleNetworkAvailabilityChanged;
        try
        {
            PowerManager.SystemSuspendStatusChanged += HandleSuspendStatusChanged;
            powerRegistered = true;
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.COMException or TypeInitializationException)
        {
            System.Diagnostics.Debug.WriteLine("Ping power-resume monitoring is unavailable.");
        }
    }

    private void HandleNetworkAvailabilityChanged(object? sender, NetworkAvailabilityEventArgs args)
    {
        if (args.IsAvailable) supervisor.RequestReconnect();
    }

    private void HandleSuspendStatusChanged(object? sender, object args)
    {
        if (PowerManager.SystemSuspendStatus is SystemSuspendStatus.AutoResume or SystemSuspendStatus.ManualResume)
            supervisor.RequestReconnect();
    }

    public void Dispose()
    {
        NetworkChange.NetworkAvailabilityChanged -= HandleNetworkAvailabilityChanged;
        if (powerRegistered)
        {
            PowerManager.SystemSuspendStatusChanged -= HandleSuspendStatusChanged;
            powerRegistered = false;
        }
    }
}
