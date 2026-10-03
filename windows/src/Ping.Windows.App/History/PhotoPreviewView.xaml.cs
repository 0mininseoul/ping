using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Ping.Windows.App.History;

public sealed partial class PhotoPreviewView : UserControl
{
    public PhotoPreviewView(ImageSource source, string filename, double width, double height)
    {
        InitializeComponent();
        PhotoPreviewRoot.Width = Math.Max(280, width);
        PhotoName.Text = string.IsNullOrWhiteSpace(filename) ? "사진" : filename;
        PhotoPreviewImage.Source = source; PhotoPreviewImage.Width = width; PhotoPreviewImage.Height = height;
    }
    public event EventHandler? CloseRequested;
    public void ClearImage() => PhotoPreviewImage.Source = null;
    private void Close_Click(object sender, RoutedEventArgs args) => CloseRequested?.Invoke(this, EventArgs.Empty);
}
