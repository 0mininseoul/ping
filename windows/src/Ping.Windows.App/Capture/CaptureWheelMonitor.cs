#if WINDOWS
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Ping.Windows.Core.Capture;

namespace Ping.Windows.App.Capture;

internal sealed class CaptureWheelMonitor
{
    private sealed record DisplayState(CaptureRect Bounds);
    private readonly DispatcherQueue dispatcher;
    private readonly Action<double, double, double> deliver;
    private readonly HookProcedure procedure;
    private readonly Thread thread;
    private readonly TaskCompletionSource ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly object pendingLock = new();
    private DisplayState? display, pendingDisplay;
    private double pendingDelta, pendingX, pendingY;
    private bool deliveryQueued;
    private int disposed;
    private uint threadId;
    private IntPtr hook;
    private Task? stopTask;
    internal Task Ready => ready.Task;

    internal CaptureWheelMonitor(DispatcherQueue dispatcher, Action<double, double, double> deliver)
    {
        this.dispatcher = dispatcher; this.deliver = deliver;
        procedure = HandleMouse;
        thread = new(Run) { IsBackground = true, Name = "Ping viewport wheel" };
        thread.Start();
    }

    internal void SetDisplay(CaptureRect? bounds)
    {
        var next = bounds is { IsUsable: true } value ? new DisplayState(value) : null;
        if (Volatile.Read(ref display) != next) Volatile.Write(ref display, next);
    }

    private void Run()
    {
        try
        {
            threadId = GetCurrentThreadId();
            PeekMessage(out _, IntPtr.Zero, 0, 0, 0);
            if (Volatile.Read(ref disposed) != 0) { ready.TrySetResult(); return; }
            hook = SetWindowsHookEx(14, procedure, GetModuleHandle(null), 0);
            if (hook == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            ready.TrySetResult();
            while (true)
            {
                var result = GetMessage(out var message, IntPtr.Zero, 0, 0);
                if (result == 0) break;
                if (result < 0) throw new Win32Exception(Marshal.GetLastWin32Error());
                TranslateMessage(ref message); DispatchMessage(ref message);
            }
        }
        catch (Exception error) { ready.TrySetException(error); System.Diagnostics.Debug.WriteLine($"Ping viewport wheel stopped: {error.Message}"); }
        finally
        {
            if (hook != IntPtr.Zero && !UnhookWindowsHookEx(hook)) System.Diagnostics.Debug.WriteLine("Ping viewport wheel unhook failed; owning thread is exiting.");
            hook = IntPtr.Zero;
            GC.KeepAlive(procedure);
        }
    }

    private IntPtr HandleMouse(int code, nuint message, IntPtr data)
    {
        var handled = false;
        try
        {
            var snapshot = Volatile.Read(ref display);
            if (code >= 0 && message == 0x020A && snapshot is not null && Volatile.Read(ref disposed) == 0 && CaptureViewportInput.AltPressed)
            {
                var mouse = Marshal.PtrToStructure<MousePacket>(data);
                if (Contains(snapshot.Bounds, mouse.Point.X, mouse.Point.Y))
                {
                    var delta = (short)(mouse.MouseData >> 16);
                    lock (pendingLock)
                    {
                        if (!ReferenceEquals(pendingDisplay, snapshot)) pendingDelta = 0;
                        pendingDisplay = snapshot;
                        pendingDelta = Math.Clamp(pendingDelta + delta, -1440, 1440);
                        pendingX = mouse.Point.X; pendingY = mouse.Point.Y;
                        if (!deliveryQueued)
                        {
                            deliveryQueued = true;
                            if (!dispatcher.TryEnqueue(DeliverPending)) { deliveryQueued = false; pendingDelta = 0; }
                        }
                        handled = deliveryQueued;
                    }
                }
            }
        }
        catch (Exception error) { System.Diagnostics.Debug.WriteLine($"Ping viewport input ignored: {error.Message}"); }
        return handled ? new IntPtr(1) : CallNextHookEx(hook, code, message, data);
    }

    private void DeliverPending()
    {
        DisplayState? snapshot; double delta, x, y;
        lock (pendingLock)
        {
            snapshot = pendingDisplay; delta = pendingDelta; x = pendingX; y = pendingY;
            deliveryQueued = false; pendingDelta = 0;
        }
        if (Volatile.Read(ref disposed) == 0 && snapshot is not null && ReferenceEquals(snapshot, Volatile.Read(ref display))) deliver(delta, x, y);
    }

    internal Task StopAsync() => stopTask ??= StopCoreAsync();
    private async Task StopCoreAsync()
    {
        Interlocked.Exchange(ref disposed, 1);
        Volatile.Write(ref display, null);
        try { await Ready; } catch { }
        if (thread.IsAlive) PostThreadMessage(threadId, 0x0012, 0, 0);
        await Task.Run(thread.Join);
    }

    internal static bool Contains(CaptureRect bounds, double x, double y) => bounds.IsUsable && double.IsFinite(x) && double.IsFinite(y)
        && x >= bounds.X && x <= bounds.Right && y >= bounds.Y && y <= bounds.Bottom;
    private delegate IntPtr HookProcedure(int code, nuint message, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct MousePacket { public Point Point; public uint MouseData, Flags, Time; public nuint ExtraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct Message { public IntPtr Window; public uint Id; public nuint WParam; public nint LParam; public uint Time; public Point Point; public uint Private; }
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string? name);
    [DllImport("user32.dll", EntryPoint = "SetWindowsHookExW", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, HookProcedure callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, nuint message, IntPtr data);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll", EntryPoint = "GetMessageW", SetLastError = true)] private static extern int GetMessage(out Message message, IntPtr window, uint minimum, uint maximum);
    [DllImport("user32.dll", EntryPoint = "PeekMessageW")] private static extern bool PeekMessage(out Message message, IntPtr window, uint minimum, uint maximum, uint remove);
    [DllImport("user32.dll")] private static extern bool TranslateMessage(ref Message message);
    [DllImport("user32.dll", EntryPoint = "DispatchMessageW")] private static extern IntPtr DispatchMessage(ref Message message);
    [DllImport("user32.dll", EntryPoint = "PostThreadMessageW", SetLastError = true)] private static extern bool PostThreadMessage(uint thread, uint message, nuint wParam, nint lParam);
}
#endif
