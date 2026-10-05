#if PING_UI_SMOKE
using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.App.History;
using WinRT.Interop;
using global::Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

internal static class MessengerInputSmoke
{
    public static async Task ChordAsync(Window window, TextBox box, ushort modifier, ushort key)
    {
        await FocusAsync(window, box); box.Focus(FocusState.Programmatic); await Task.Delay(50);
        if (GetForegroundWindow() != WindowNative.GetWindowHandle(window)) throw new InvalidOperationException("Diagnostic messenger lost keyboard focus.");
        Send([Key(modifier), Key(key), Key(key, true), Key(modifier, true)]);
        await Task.Delay(100);
    }

    public static async Task DropAsync(Window window, HistoryWindow shell, StorageFile file)
    {
        var root = (Grid)shell.FindName("Root");
        var source = new Border { Width = 100, Height = 40, Margin = new(20, 180, 0, 0), HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top, Background = new SolidColorBrush(Colors.CornflowerBlue), CanDrag = true,
            Child = new TextBlock { Text = "소유 QA 사진", VerticalAlignment = VerticalAlignment.Center } };
        var started = false;
        source.DragStarting += (_, args) => { started = true; args.Data.SetStorageItems([file]); args.AllowedOperations = global::Windows.ApplicationModel.DataTransfer.DataPackageOperation.Copy; };
        source.PointerPressed += async (_, args) => await source.StartDragAsync(args.GetCurrentPoint(source));
        root.Children.Add(source);
        GetCursorPos(out var original);
        try
        {
            await FocusAsync(window, source); await Task.Delay(80);
            var p = source.TransformToVisual((UIElement)window.Content).TransformPoint(new(50, 20));
            var scale = shell.XamlRoot.RasterizationScale;
            var start = new NativePoint { X = (int)Math.Round(p.X * scale), Y = (int)Math.Round(p.Y * scale) };
            var target = new NativePoint { X = (int)(shell.ActualWidth * 0.8 * scale), Y = (int)(shell.ActualHeight * 0.6 * scale) };
            ClientToScreen(WindowNative.GetWindowHandle(window), ref start);
            ClientToScreen(WindowNative.GetWindowHandle(window), ref target);
            SetCursorPos(start.X, start.Y); await Task.Delay(60); Send([Mouse(0x2)]);
            for (var i = 1; i <= 8; i++)
            {
                SetCursorPos(start.X + (target.X - start.X) * i / 8, start.Y + (target.Y - start.Y) * i / 8);
                await Task.Delay(60);
            }
            Send([Mouse(0x4)]); await Task.Delay(100);
            if (!started) throw new InvalidOperationException("Owned pointer fixture did not begin a native drag.");
        }
        finally { Send([Mouse(0x4)]); SetCursorPos(original.X, original.Y); root.Children.Remove(source); }
    }
    private static async Task FocusAsync(Window window, FrameworkElement target)
    {
        var hwnd = WindowNative.GetWindowHandle(window);
        if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return;
        GetCursorPos(out var original);
        try
        {
            SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, 0x43);
            var p = target.TransformToVisual((UIElement)window.Content).TransformPoint(new(target.ActualWidth / 2, target.ActualHeight / 2));
            var scale = target.XamlRoot.RasterizationScale;
            var point = new NativePoint { X = (int)Math.Round(p.X * scale), Y = (int)Math.Round(p.Y * scale) };
            ClientToScreen(hwnd, ref point);
            SetCursorPos(point.X, point.Y); Send([Mouse(0x2), Mouse(0x4)]);
            await Task.Delay(100);
        }
        finally { SetWindowPos(hwnd, new IntPtr(-2), 0, 0, 0, 0, 0x13); SetCursorPos(original.X, original.Y); }
    }
    private static NativeInput Key(ushort key, bool up = false) => new() { Type = 1, VirtualKey = key, KeyboardFlags = (up ? 2U : 0U) | (key == 0x2D ? 1U : 0U) };
    private static NativeInput Mouse(uint flags) => new() { Type = 0, MouseFlags = flags };
    private static void Send(NativeInput[] inputs)
    {
        if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<NativeInput>()) != inputs.Length)
            throw new InvalidOperationException("Windows rejected owned diagnostic input.");
    }
    [StructLayout(LayoutKind.Explicit, Size = 40)] private struct NativeInput
    {
        [FieldOffset(0)] public uint Type;
        [FieldOffset(8)] public ushort VirtualKey;
        [FieldOffset(12)] public uint KeyboardFlags;
        [FieldOffset(20)] public uint MouseFlags;
    }
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }
    [DllImport("user32.dll")] private static extern uint SendInput(uint count, NativeInput[] inputs, int size);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref NativePoint point);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
}
#endif
