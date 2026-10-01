#if WINDOWS
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using global::Windows.Storage.Streams;

namespace Ping.Windows.App.Setup;

internal sealed class DevicePairingPresenter : IDisposable
{
    private readonly DevicePairingViewModel model;
    private readonly Image image;
    private readonly DispatcherQueueTimer expiry;
    private bool disposed;
    private XamlRoot? root;

    internal DevicePairingPresenter(DevicePairingViewModel model, Image image)
    {
        this.model = model; this.image = image;
        model.PropertyChanged += HandleChanged;
        image.Loaded += HandleLoaded;
        expiry = image.DispatcherQueue.CreateTimer(); expiry.Interval = TimeSpan.FromSeconds(15);
        expiry.Tick += (_, _) =>
        {
            if (model.IsActive && !model.IsLoading && model.Image is { } current
                && current.ExpiresAt <= DateTimeOffset.UtcNow.AddMinutes(1)) _ = model.OpenAsync();
        };
    }
    internal void SetVisible(bool visible)
    {
        if (disposed) return;
        if (visible)
        {
            expiry.Start();
            if (!model.IsActive) _ = model.OpenAsync();
        }
        else Clear();
    }
    internal void Clear() { expiry.Stop(); model.Deactivate(); image.Source = null; }
    private async void HandleChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs args)
    {
        if (args.PropertyName != nameof(DevicePairingViewModel.Image)) return;
        var current = model.Image;
        image.Source = null;
        if (current is null || disposed) return;
        try
        {
            using var stream = new InMemoryRandomAccessStream();
            await stream.WriteAsync(current.Png.AsBuffer()); stream.Seek(0);
            var source = new BitmapImage(); await source.SetSourceAsync(stream);
            if (!disposed && ReferenceEquals(model.Image, current))
            {
                FitPixelGrid(source);
                image.Source = source;
            }
        }
        catch { if (!disposed && ReferenceEquals(model.Image, current)) model.ReportRenderingFailure(); }
    }
    private void HandleLoaded(object sender, RoutedEventArgs args)
    {
        if (ReferenceEquals(root, image.XamlRoot)) return;
        if (root is not null) root.Changed -= HandleRootChanged;
        root = image.XamlRoot;
        if (root is not null) root.Changed += HandleRootChanged;
        if (image.Source is BitmapImage source) FitPixelGrid(source);
    }
    private void HandleRootChanged(XamlRoot sender, XamlRootChangedEventArgs args)
    {
        if (image.Source is BitmapImage source) FitPixelGrid(source);
    }
    private void FitPixelGrid(BitmapImage source)
    {
        // Keep QR modules on their encoded pixel grid instead of resampling them.
        var scale = image.XamlRoot?.RasterizationScale ?? 1;
        image.Width = source.PixelWidth / scale; image.Height = source.PixelHeight / scale;
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; model.PropertyChanged -= HandleChanged; image.Loaded -= HandleLoaded;
        if (root is not null) root.Changed -= HandleRootChanged;
        Clear();
    }
}
#endif
