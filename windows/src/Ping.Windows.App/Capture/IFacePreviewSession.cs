using Microsoft.UI.Xaml.Controls;

namespace Ping.Windows.App.Capture;

public interface IFacePreviewSession
{
    Task StartPreviewAsync(MediaPlayerElement preview, CancellationToken cancellationToken = default);
    Task StopPreviewAsync(MediaPlayerElement preview);
}
