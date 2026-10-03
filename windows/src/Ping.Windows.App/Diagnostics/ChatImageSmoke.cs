#if PING_UI_SMOKE
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Ping.Windows.App.History;
using Ping.Windows.Core.Backend;
using global::Windows.Graphics.Imaging;
using global::Windows.Storage;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    private static async Task VerifyChatImagePreviewAsync()
    {
        var file = await (await StorageFolder.GetFolderFromPathAsync(OutputDirectory!)).CreateFileAsync("owned-photo.png", CreationCollisionOption.ReplaceExisting);
        using (var stream = await file.OpenAsync(FileAccessMode.ReadWrite))
        {
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
            var pixels = new byte[960 * 640 * 4];
            for (var y = 0; y < 640; y++) for (var x = 0; x < 960; x++)
            {
                var i = (y * 960 + x) * 4;
                pixels[i] = (byte)(140 + x / 12); pixels[i + 1] = (byte)(80 + y / 5);
                pixels[i + 2] = (byte)(220 - y / 8); pixels[i + 3] = 255;
            }
            encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Straight, 960, 640, 96, 96, pixels);
            await encoder.FlushAsync();
        }
        var rpc = new FixtureRpc { IncludePhoto = true }; var storage = new FixtureStorage { PhotoPath = file.Path };
        var vm = new HistoryViewModel(new(rpc), new(rpc, storage), new(rpc), new(rpc), storage, () => "me", new FixtureLinks());
        var window = new MainWindow(); window.InitializeTrayWindowBehavior();
        var shell = new HistoryWindow(window, vm, (_, _) => throw new NotSupportedException(), (_, _) => Task.CompletedTask, new(rpc, storage), loadOnStart: false);
        window.AttachMessenger(shell); window.ShowShell();
        try
        {
            shell.RequestedTheme = ElementTheme.Light;
            await shell.ReloadRoomsAsync(); await Task.Delay(150);
            var photo = vm.Chats.Single(c => c.Message.Id == "photo");
            await UntilAsync(() => photo.ImageSource?.PixelWidth == 960);
            var button = Descendants(shell).OfType<Button>().FirstOrDefault(b => b.Name == "PhotoButton" && b.DataContext is TimelineHistoryItem { Chat.Message.Id: "photo" });
            Check(button is { IsEnabled: true }, "loaded photo tile exposes a keyboard-accessible native preview action");
            Check(Math.Abs(button!.ActualWidth - 240) < 1 && Math.Abs(button.ActualHeight - 160) < 1,
                "photo tile preserves the Mac240-by260 bounding box and original image aspect");
            void Open() => ((IInvokeProvider)new ButtonAutomationPeer(button!).GetPattern(PatternInterface.Invoke)).Invoke();
            DependencyObject[] Popups() => VisualTreeHelper.GetOpenPopupsForXamlRoot(shell.XamlRoot).SelectMany(p => Descendants(p.Child).Append(p.Child)).ToArray();
            Open();
            await UntilAsync(() => Popups().OfType<Image>().Any(i => i.Name == "PhotoPreviewImage"));
            var preview = Popups().OfType<Image>().Single(i => i.Name == "PhotoPreviewImage");
            Check(ReferenceEquals(preview.Source, photo.ImageSource) && preview.ActualWidth > 320 && preview.ActualHeight > 240,
                "photo preview enlarges the cached image without another network download");
            Check(Popups().OfType<TextBlock>().Any(t => t.Text == "공유한 사진.png"), "photo preview shows the original filename");
            await Task.Delay(250);
            await RenderAsync(Popups().OfType<Grid>().Single(g => g.Name == "PhotoPreviewRoot"), "messenger-photo-preview.png");
            ((IInvokeProvider)new ButtonAutomationPeer(Popups().OfType<Button>().Single(b => b.Name == "ClosePhotoPreviewButton")).GetPattern(PatternInterface.Invoke)).Invoke();
            await UntilAsync(() => !Popups().OfType<Image>().Any(i => i.Name == "PhotoPreviewImage"));
            Check(preview.Source is null, "closing photo preview clears the displayed image reference");
            Open(); await UntilAsync(() => Popups().OfType<Image>().Any());
            await shell.FocusRoomAsync("b");
            await UntilAsync(() => !Popups().OfType<Image>().Any(i => i.Name == "PhotoPreviewImage"));
            Check(true, "changing rooms dismisses the previous room photo preview");
            await shell.FocusRoomAsync("a"); await Task.Delay(100);
            button = Descendants(shell).OfType<Button>().Single(b => b.Name == "PhotoButton" && b.DataContext is TimelineHistoryItem { Chat.Message.Id: "photo" });
            Open(); await UntilAsync(() => Popups().OfType<Image>().Any());
            await shell.DetachAsync();
            await UntilAsync(() => !Popups().OfType<Image>().Any(i => i.Name == "PhotoPreviewImage"));
            Check(true, "account runtime detach dismisses old photo preview");
            var invalid = await (await StorageFolder.GetFolderFromPathAsync(OutputDirectory!)).CreateFileAsync("invalid-owned-photo.png", CreationCollisionOption.ReplaceExisting);
            await FileIO.WriteTextAsync(invalid, "owned invalid decoder fixture");
            var currentPhoto = vm.Chats.Single(c => c.Message.Id == "photo");
            currentPhoto.SetImagePath(invalid.Path);
            await UntilAsync(() => currentPhoto.ImageSource is null);
            Check(!currentPhoto.CanPreviewImage && currentPhoto.AttachmentStatus == "사진을 불러올 수 없어요",
                "invalid received image fails gracefully and disables preview instead of opening an empty panel");
        }
        finally { await shell.DetachAsync(); window.CloseForQuit(); }
    }
}
#endif
