using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Ping.Windows.App.Tray;

public enum TrayCommand
{
    OpenPing,
    NewFacePing,
    NewScreenFacePing,
    QuickScreenFacePing,
    Settings,
    Quit
}

public sealed class TrayIconController : IDisposable
{
    private const int IconId = 1;
    private const uint CallbackMessage = 0x8051;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmRButtonUp = 0x0205;
    private const uint WmContextMenu = 0x007B;
    private const uint WmNull = 0x0000;
    private const uint NinSelect = 0x0400;
    private const uint ImageIcon = 1;
    private const uint LrLoadFromFile = 0x0010;
    private const uint LrDefaultSize = 0x0040;
    private static readonly IntPtr SystemApplicationIcon = new(32512);
    private static readonly Dictionary<IntPtr, TrayIconController> ControllersByWindow = [];
    private static readonly WndProc WindowProcedure = StaticWindowProcedure;
    private readonly Action<TrayCommand> dispatch;
    private readonly IntPtr hwnd;
    private readonly uint taskbarCreatedMessage;
    private readonly IntPtr iconHandle;
    private readonly bool ownsIconHandle;
    private bool iconVisible;
    private bool disposed;

    public TrayIconController(Action<TrayCommand> dispatch)
    {
        this.dispatch = dispatch;

        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("Ping tray integration requires Win32 Shell_NotifyIcon.");
        }

        hwnd = CreateMessageWindow();
        taskbarCreatedMessage = RegisterWindowMessage("TaskbarCreated");
        (iconHandle, ownsIconHandle) = LoadPingIcon();
        ControllersByWindow[hwnd] = this;
    }

    public void AddOrUpdateIcon()
    {
        ObjectDisposedException.ThrowIf(disposed, this);

        var data = CreateNotifyIconData();
        if (!ShellNotifyIcon(iconVisible ? NotifyIconMessage.Modify : NotifyIconMessage.Add, ref data))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not add Ping tray icon.");
        }

        if (!iconVisible)
        {
            data.uVersion = 4;
            ShellNotifyIcon(NotifyIconMessage.SetVersion, ref data);
            iconVisible = true;
        }
    }

    public void RemoveIcon()
    {
        if (!iconVisible)
        {
            return;
        }

        var data = CreateNotifyIconData();
        ShellNotifyIcon(NotifyIconMessage.Delete, ref data);
        iconVisible = false;
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        RemoveIcon();
        ControllersByWindow.Remove(hwnd);
        if (ownsIconHandle && iconHandle != IntPtr.Zero)
        {
            DestroyIcon(iconHandle);
        }

        DestroyWindow(hwnd);
        disposed = true;
    }

    private void HandleMessage(uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == taskbarCreatedMessage)
        {
            iconVisible = false;
            TryAddOrUpdateIcon();
            return;
        }

        if (message != CallbackMessage)
        {
            return;
        }

        try
        {
            var trayEvent = LowWord(lParam);
            if (trayEvent is WmLButtonUp or NinSelect)
            {
                dispatch(TrayCommand.OpenPing);
            }
            else if (trayEvent is WmRButtonUp or WmContextMenu)
            {
                ShowContextMenu();
            }
        }
        catch (Exception exception)
        {
            Debug.WriteLine($"Ping tray callback failed: {exception}");
        }
    }

    private bool TryAddOrUpdateIcon()
    {
        try
        {
            AddOrUpdateIcon();
            return true;
        }
        catch (Win32Exception)
        {
            return false;
        }
    }

    private void ShowContextMenu()
    {
        var menu = CreatePopupMenu();
        if (menu == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not create Ping tray menu.");
        }

        try
        {
            AppendMenu(menu, 0, (UIntPtr)(uint)TrayMenuId.OpenPing, "Open Ping");
            AppendMenu(menu, 0, (UIntPtr)(uint)TrayMenuId.NewFacePing, "New Face Ping");
            AppendMenu(menu, 0, (UIntPtr)(uint)TrayMenuId.NewScreenFacePing, "New Screen+Face Ping");
            AppendMenu(menu, 0, (UIntPtr)(uint)TrayMenuId.QuickScreenFacePing, "Quick Screen+Face Ping");
            AppendMenu(menu, 0x0800, UIntPtr.Zero, null);
            AppendMenu(menu, 0, (UIntPtr)(uint)TrayMenuId.Settings, "Settings");
            AppendMenu(menu, 0, (UIntPtr)(uint)TrayMenuId.Quit, "Quit");

            GetCursorPos(out var point);
            SetForegroundWindow(hwnd);
            var selected = TrackPopupMenu(menu, 0x0100, point.X, point.Y, 0, hwnd, IntPtr.Zero);
            PostMessage(hwnd, WmNull, IntPtr.Zero, IntPtr.Zero);
            DispatchMenuSelection(selected);
        }
        finally
        {
            DestroyMenu(menu);
        }
    }

    private void DispatchMenuSelection(uint selected)
    {
        var command = selected switch
        {
            (uint)TrayMenuId.OpenPing => TrayCommand.OpenPing,
            (uint)TrayMenuId.NewFacePing => TrayCommand.NewFacePing,
            (uint)TrayMenuId.NewScreenFacePing => TrayCommand.NewScreenFacePing,
            (uint)TrayMenuId.QuickScreenFacePing => TrayCommand.QuickScreenFacePing,
            (uint)TrayMenuId.Settings => TrayCommand.Settings,
            (uint)TrayMenuId.Quit => TrayCommand.Quit,
            _ => (TrayCommand?)null
        };

        if (command is { } trayCommand)
        {
            dispatch(trayCommand);
        }
    }

    private NotifyIconData CreateNotifyIconData() => new()
    {
        cbSize = (uint)Marshal.SizeOf<NotifyIconData>(),
        hWnd = hwnd,
        uID = IconId,
        uFlags = 0x0001 | 0x0002 | 0x0004,
        uCallbackMessage = CallbackMessage,
        hIcon = iconHandle,
        szTip = "Ping",
        szInfo = string.Empty,
        szInfoTitle = string.Empty
    };

    private static IntPtr CreateMessageWindow()
    {
        var instance = GetModuleHandle(null);
        var className = $"PingTrayMessageWindow-{Guid.NewGuid():N}";
        var wndClass = new WndClass
        {
            lpfnWndProc = WindowProcedure,
            hInstance = instance,
            lpszClassName = className
        };

        if (RegisterClass(ref wndClass) == 0)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not register Ping tray message window.");
        }

        var hwnd = CreateWindowEx(
            0,
            className,
            "Ping Tray",
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
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not create Ping tray message window.");
        }

        return hwnd;
    }

    private static IntPtr StaticWindowProcedure(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (ControllersByWindow.TryGetValue(hwnd, out var controller))
        {
            controller.HandleMessage(message, wParam, lParam);
        }

        return DefWindowProc(hwnd, message, wParam, lParam);
    }

    private static uint LowWord(IntPtr value) => (uint)(value.ToInt64() & 0xffff);

    private static (IntPtr Handle, bool OwnsHandle) LoadPingIcon()
    {
        var iconPath = Path.Combine(AppContext.BaseDirectory, "Assets", "Ping.ico");
        if (File.Exists(iconPath))
        {
            var handle = LoadImage(
                IntPtr.Zero,
                iconPath,
                ImageIcon,
                0,
                0,
                LrLoadFromFile | LrDefaultSize);
            if (handle != IntPtr.Zero)
            {
                return (handle, true);
            }
        }

        var fallback = LoadIcon(IntPtr.Zero, SystemApplicationIcon);
        if (fallback == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not load Ping tray icon.");
        }

        return (fallback, false);
    }

    private enum TrayMenuId : uint
    {
        OpenPing = 100,
        NewFacePing = 101,
        NewScreenFacePing = 102,
        QuickScreenFacePing = 103,
        Settings = 104,
        Quit = 105
    }

    private enum NotifyIconMessage : uint
    {
        Add = 0x00000000,
        Modify = 0x00000001,
        Delete = 0x00000002,
        SetVersion = 0x00000004
    }

    private delegate IntPtr WndProc(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public IntPtr hIcon;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;

        public uint dwState;
        public uint dwStateMask;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szInfo;

        public uint uVersion;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string szInfoTitle;

        public uint dwInfoFlags;
        public Guid guidItem;
        public IntPtr hBalloonIcon;
    }

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

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int X;
        public int Y;
    }

    [DllImport("shell32.dll", SetLastError = true, CharSet = CharSet.Unicode, EntryPoint = "Shell_NotifyIconW")]
    private static extern bool ShellNotifyIcon(NotifyIconMessage dwMessage, ref NotifyIconData lpData);

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

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern uint RegisterWindowMessage(string lpString);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr LoadIcon(IntPtr hInstance, IntPtr lpIconName);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadImage(
        IntPtr hInst,
        string name,
        uint type,
        int cx,
        int cy,
        uint fuLoad);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr CreatePopupMenu();

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool AppendMenu(IntPtr hMenu, uint uFlags, UIntPtr uIDNewItem, string? lpNewItem);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyMenu(IntPtr hMenu);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetCursorPos(out Point lpPoint);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint TrackPopupMenu(IntPtr hMenu, uint uFlags, int x, int y, int nReserved, IntPtr hWnd, IntPtr prcRect);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? lpModuleName);
}
