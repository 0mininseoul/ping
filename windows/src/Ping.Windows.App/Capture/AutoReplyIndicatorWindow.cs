using System.Runtime.InteropServices;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Ping.Windows.App.Capture;

internal sealed class AutoReplyIndicatorWindow : Window, IAsyncDisposable
{
    private readonly TextBlock sender;
    private readonly ProgressBar progress;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer timer;
    private readonly DateTimeOffset started = DateTimeOffset.UtcNow;
    private bool closed;
    internal string SenderText => sender.Text;

    public AutoReplyIndicatorWindow(string senderNickname)
    {
        sender = new() { Text = $"{senderNickname}님에게 보냅니다", FontSize = 11, TextTrimming = TextTrimming.CharacterEllipsis };
        progress = new() { Minimum = 0, Maximum = 3, Height = 2, VerticalAlignment = VerticalAlignment.Bottom,
            Foreground = new SolidColorBrush(Color.FromArgb(255, 255, 59, 48)) };
        var text = new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center };
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        title.Children.Add(new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 10, Height = 10, Fill = progress.Foreground });
        title.Children.Add(new TextBlock { Text = "자동 회신 녹화 중", FontSize = 13, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        text.Children.Add(title);
        text.Children.Add(sender);
        var grid = new Grid();
        grid.Children.Add(text);
        grid.Children.Add(progress);
        Content = new Border { Padding = new Thickness(12, 4, 12, 0), CornerRadius = new CornerRadius(12),
            BorderThickness = new Thickness(2), BorderBrush = progress.Foreground,
            Background = Application.Current.Resources["PingSurfaceBrush"] as Brush ?? new SolidColorBrush(Colors.DarkSlateGray), Child = grid };
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var style = GetWindowLongPtr(hwnd, -20).ToInt64();
        SetWindowLongPtr(hwnd, -20, new IntPtr((style | 0x08000080L) & ~0x00040000L));
        var presenter = OverlappedPresenter.CreateForToolWindow();
        presenter.SetBorderAndTitleBar(false, false);
        presenter.IsAlwaysOnTop = true;
        presenter.IsResizable = false;
        AppWindow.SetPresenter(presenter);
        var scale = GetDpiForWindow(hwnd) / 96d;
        AppWindow.ResizeClient(new((int)Math.Round(232 * scale), (int)Math.Round(56 * scale)));
        var work = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        AppWindow.Move(new(work.X + work.Width - AppWindow.Size.Width - (int)Math.Round(20 * scale), work.Y + (int)Math.Round(20 * scale)));
        timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(100);
        timer.Tick += HandleTick;
        Closed += (_, _) => { closed = true; timer.Stop(); timer.Tick -= HandleTick; };
    }

    private void HandleTick(Microsoft.UI.Dispatching.DispatcherQueueTimer senderTimer, object args) =>
        progress.Value = Math.Min(3, (DateTimeOffset.UtcNow - started).TotalSeconds);

    public void Present() { AppWindow.Show(false); timer.Start(); }

    public ValueTask DisposeAsync()
    {
        if (DispatcherQueue.HasThreadAccess) { if (!closed) Close(); return ValueTask.CompletedTask; }
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!DispatcherQueue.TryEnqueue(() =>
        {
            try { if (!closed) Close(); completion.TrySetResult(); }
            catch (Exception error) { completion.TrySetException(error); }
        })) completion.TrySetException(new InvalidOperationException("녹화 표시창을 닫을 UI를 사용할 수 없습니다."));
        return new(completion.Task);
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
}
