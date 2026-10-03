using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Ping.Windows.App.UI;

namespace Ping.Windows.App.History;

public sealed partial class HistoryWindow
{
    private Flyout? photoPreview;
    private PhotoPreviewView? photoPreviewContent;
    private string? photoRoomId;

    private void ShowPhotoPreview_Click(object sender, RoutedEventArgs args)
    {
        if (detached || sender is not Button button || ChatItem(sender) is not { CanPreviewImage: true } row
            || row.Message.RoomId != viewModel.SelectedRoom?.Id || XamlRoot is null) return;
        ClosePhotoPreview();
        var widthLimit = Math.Max(240, Math.Min(780, XamlRoot.Size.Width - 72));
        var heightLimit = Math.Max(160, Math.Min(620, XamlRoot.Size.Height - 132));
        var ratio = row.ImageSource!.PixelWidth / (double)row.ImageSource.PixelHeight;
        var width = Math.Min(widthLimit, heightLimit * ratio);
        var height = width / ratio;
        var content = new PhotoPreviewView(row.ImageSource, row.MediaFileName, width, height);
        content.CloseRequested += (_, _) => ClosePhotoPreview();
        photoPreviewContent = content;
        var style = new Style(typeof(FlyoutPresenter));
        style.Setters.Add(new Setter(FrameworkElement.RequestedThemeProperty, ActualTheme));
        style.Setters.Add(new Setter(FlyoutPresenter.PaddingProperty, new Thickness(14)));
        style.Setters.Add(new Setter(FlyoutPresenter.MaxWidthProperty, widthLimit + 28));
        style.Setters.Add(new Setter(FlyoutPresenter.MaxHeightProperty, heightLimit + 80));
        style.Setters.Add(new Setter(FlyoutPresenter.CornerRadiusProperty, new CornerRadius(16)));
        var flyout = new Flyout { Content = content, FlyoutPresenterStyle = style };
        flyout.Closed += (_, _) => { if (ReferenceEquals(photoPreview, flyout)) ClearPhotoPreview(); };
        photoPreview = flyout; photoRoomId = row.Message.RoomId;
        flyout.ShowAt(button);
    }

    private void ClosePhotoPreview()
    {
        photoPreview?.Hide(); ClearPhotoPreview();
    }
    private void ClearPhotoPreview()
    {
        photoPreviewContent?.ClearImage();
        photoPreviewContent = null; photoPreview = null; photoRoomId = null;
    }
    private void PhotoTile_Loaded(object sender, RoutedEventArgs args) => ClipPhotoTile(sender);
    private void PhotoTile_SizeChanged(object sender, SizeChangedEventArgs args) => ClipPhotoTile(sender);
    private static void ClipPhotoTile(object sender)
    {
        if (sender is FrameworkElement tile) RoundedCompositionClip.Apply(tile, tile.ActualWidth, tile.ActualHeight, 14);
    }
}
