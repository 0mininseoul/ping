using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace Ping.Windows.App.Hotkeys;

public sealed class GlobalHotkeyManager : IDisposable
{
    private readonly IHotkeyRegistrar registrar;
    private readonly Dictionary<HotkeyCommand, int> commandIds = [];
    private readonly Dictionary<int, HotkeyCommand> idCommands = [];
    private int nextId = 0x5100;
    private bool disposed;

    [SupportedOSPlatform("windows")]
    public GlobalHotkeyManager()
        : this(new Win32HotkeyRegistrar())
    {
    }

    public GlobalHotkeyManager(IHotkeyRegistrar registrar)
    {
        this.registrar = registrar;
        this.registrar.HotkeyPressed += HandleRegistrarHotkeyPressed;
    }

    public event EventHandler<HotkeyCommand>? HotkeyPressed;

    public HotkeyRegistrationResult Register(HotkeyCommand command, HotkeyBinding binding)
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        var id = nextId++;
        var registrarResult = registrar.Register(id, binding);
        if (registrarResult.Status == HotkeyRegistrarStatus.Success)
        {
            if (commandIds.Remove(command, out var existingId))
            {
                idCommands.Remove(existingId);
                registrar.Unregister(existingId);
            }

            commandIds[command] = id;
            idCommands[id] = command;
            return HotkeyRegistrationResult.Success(command, binding);
        }

        return registrarResult.Status == HotkeyRegistrarStatus.Conflict
            ? HotkeyRegistrationResult.Conflict(command, binding, registrarResult.Message)
            : HotkeyRegistrationResult.Error(command, binding, registrarResult.Message);
    }

    public void UnregisterAll()
    {
        foreach (var id in commandIds.Values)
        {
            registrar.Unregister(id);
        }

        commandIds.Clear();
        idCommands.Clear();
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        UnregisterAll();
        registrar.HotkeyPressed -= HandleRegistrarHotkeyPressed;
        registrar.Dispose();
        disposed = true;
    }

    private void HandleRegistrarHotkeyPressed(object? sender, int id)
    {
        if (idCommands.TryGetValue(id, out var command))
        {
            HotkeyPressed?.Invoke(this, command);
        }
    }
}

public enum HotkeyRegistrationStatus
{
    Success,
    Conflict,
    Error
}

public sealed record HotkeyRegistrationResult(
    HotkeyRegistrationStatus Status,
    HotkeyCommand Command,
    HotkeyBinding Binding,
    string Message)
{
    public static HotkeyRegistrationResult Success(HotkeyCommand command, HotkeyBinding binding) =>
        new(HotkeyRegistrationStatus.Success, command, binding, "Registered.");

    public static HotkeyRegistrationResult Conflict(HotkeyCommand command, HotkeyBinding binding, string message) =>
        new(HotkeyRegistrationStatus.Conflict, command, binding, message);

    public static HotkeyRegistrationResult Error(HotkeyCommand command, HotkeyBinding binding, string message) =>
        new(HotkeyRegistrationStatus.Error, command, binding, message);
}

public interface IHotkeyRegistrar : IDisposable
{
    event EventHandler<int>? HotkeyPressed;

    HotkeyRegistrarResult Register(int id, HotkeyBinding binding);

    void Unregister(int id);
}

public enum HotkeyRegistrarStatus
{
    Success,
    Conflict,
    Error
}

public sealed record HotkeyRegistrarResult(HotkeyRegistrarStatus Status, string Message)
{
    public static HotkeyRegistrarResult Success() => new(HotkeyRegistrarStatus.Success, "Registered.");

    public static HotkeyRegistrarResult Conflict(string message) => new(HotkeyRegistrarStatus.Conflict, message);

    public static HotkeyRegistrarResult Error(string message) => new(HotkeyRegistrarStatus.Error, message);
}

[SupportedOSPlatform("windows")]
internal sealed class Win32HotkeyRegistrar : IHotkeyRegistrar
{
    private const int WmHotkey = 0x0312;
    private const int ErrorHotkeyAlreadyRegistered = 1409;
    private static readonly Dictionary<IntPtr, Win32HotkeyRegistrar> RegistrarsByWindow = [];
    private static readonly WndProc WindowProcedure = StaticWindowProcedure;
    private readonly IntPtr hwnd;
    private bool disposed;

    public Win32HotkeyRegistrar()
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Global hotkeys require Win32 RegisterHotKey.");
        }

        hwnd = CreateMessageWindow();
        RegistrarsByWindow[hwnd] = this;
    }

    public event EventHandler<int>? HotkeyPressed;

    public HotkeyRegistrarResult Register(int id, HotkeyBinding binding)
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        if (RegisterHotKey(hwnd, id, binding.ToModifierFlags(), binding.ToVirtualKey()))
        {
            return HotkeyRegistrarResult.Success();
        }

        var error = Marshal.GetLastWin32Error();
        if (error == ErrorHotkeyAlreadyRegistered)
        {
            return HotkeyRegistrarResult.Conflict($"{binding} is already used by another app.");
        }

        return HotkeyRegistrarResult.Error(new Win32Exception(error).Message);
    }

    public void Unregister(int id)
    {
        if (!disposed)
        {
            UnregisterHotKey(hwnd, id);
        }
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        RegistrarsByWindow.Remove(hwnd);
        DestroyWindow(hwnd);
        disposed = true;
    }

    private void RaiseHotkeyPressed(int id)
    {
        HotkeyPressed?.Invoke(this, id);
    }

    private static IntPtr CreateMessageWindow()
    {
        var instance = GetModuleHandle(null);
        var className = $"PingHotkeyMessageWindow-{Guid.NewGuid():N}";
        var wndClass = new WndClass
        {
            lpfnWndProc = WindowProcedure,
            hInstance = instance,
            lpszClassName = className
        };

        if (RegisterClass(ref wndClass) == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not register Ping hotkey message window.");
        }

        var hwnd = CreateWindowEx(
            0,
            className,
            "Ping Hotkeys",
            0,
            0,
            0,
            0,
            0,
            IntPtr.Zero,
            IntPtr.Zero,
            instance,
            IntPtr.Zero);

        if (hwnd == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not create Ping hotkey message window.");
        }

        return hwnd;
    }

    private static IntPtr StaticWindowProcedure(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == WmHotkey && RegistrarsByWindow.TryGetValue(hwnd, out var registrar))
        {
            registrar.RaiseHotkeyPressed(wParam.ToInt32());
            return IntPtr.Zero;
        }

        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    private delegate IntPtr WndProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WndClass
    {
        public uint style;
        public WndProc lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        public string? lpszMenuName;
        public string lpszClassName;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern ushort RegisterClass(ref WndClass lpWndClass);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowEx(
        uint dwExStyle,
        string lpClassName,
        string lpWindowName,
        uint dwStyle,
        int x,
        int y,
        int nWidth,
        int nHeight,
        IntPtr hWndParent,
        IntPtr hMenu,
        IntPtr hInstance,
        IntPtr lpParam);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyWindow(IntPtr hWnd);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);
}
