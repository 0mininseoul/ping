#if PING_UI_SMOKE
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Media.Imaging;
using Ping.Windows.App.History;
using global::Windows.ApplicationModel.DataTransfer;
using global::Windows.Storage;
using global::Windows.Storage.Streams;
using global::Windows.Graphics.Imaging;

namespace Ping.Windows.App.Diagnostics;

internal static partial class UiSmokeRunner
{
    private static async Task VerifyImageInputAsync()
    {
        var rpc = new FixtureRpc(); var storage = new FixtureStorage();
        var vm = new HistoryViewModel(new(rpc), new(rpc, storage), new(rpc), new(rpc), storage, () => "me", new FixtureLinks());
        var window = new MainWindow(); window.InitializeTrayWindowBehavior();
        var shell = new HistoryWindow(window, vm, (_, _) => throw new NotSupportedException(), (_, _) => Task.CompletedTask, new(rpc, storage), loadOnStart: false);
        window.AttachMessenger(shell); window.ShowShell();
        DataPackage? originalClipboard = null;
        InMemoryRandomAccessStream? savedBitmap = null;
        try
        {
            await shell.ReloadRoomsAsync(); await Task.Delay(100);
            Check(Descendants(shell).OfType<Grid>().Any(g => g.Name == "ConversationSurface" && g.AllowDrop),
                "conversation accepts photo drop across the timeline and composer");
            var file = await StorageFile.GetFileFromPathAsync(Path.Combine(OutputDirectory!, "owned-photo.png"));
            var originalBytes = File.ReadAllBytes(file.Path);
            var box = Descendants(shell).OfType<TextBox>().Single(b => b.Name == "ChatBox");
            Button Button(string name) => Descendants(shell).OfType<Button>().Single(b => b.Name == name);
            void Invoke(string name) => ((IInvokeProvider)new ButtonAutomationPeer(Button(name)).GetPattern(PatternInterface.Invoke)).Invoke();
            var data = new DataPackage(); data.SetStorageItems([file]);
            vm.DraftText = "사진과 함께 보낼 문구 😊";
            await shell.ImportImageAsync(data.GetView());
            var staged = vm.DraftImagePath;
            Check(staged is not null && staged != file.Path && File.ReadAllBytes(staged).SequenceEqual(originalBytes),
                "photo input stages an owned snapshot without changing the original file");
            Check(vm.DraftImageName == "owned-photo.png" && vm.DraftText == "사진과 함께 보낼 문구 😊" && vm.CanSend,
                "attachment keeps original filename and caption ready for explicit send");
            var preview = Descendants(shell).OfType<Image>().Single(i => i.Name == "DraftPhotoImage");
            await UntilAsync(() => preview.Source is BitmapImage { PixelWidth: 960 });
            shell.RequestedTheme = ElementTheme.Light; await Task.Delay(100);
            await RenderAsync(shell, "messenger-photo-input-light.png");
            shell.RequestedTheme = ElementTheme.Dark; await Task.Delay(100);
            await RenderAsync(shell, "messenger-photo-input-dark.png");
            var invalid = await file.GetParentAsync();
            var badFile = await invalid.CreateFileAsync("not-a-photo.txt", CreationCollisionOption.ReplaceExisting);
            await FileIO.WriteTextAsync(badFile, "owned unsupported fixture");
            var bad = new DataPackage(); bad.SetStorageItems([badFile]);
            await shell.ImportImageAsync(bad.GetView());
            Check(vm.DraftImagePath == staged && vm.DraftText == "사진과 함께 보낼 문구 😊",
                "unsupported file leaves the existing photo and caption intact");
            var oversized = Path.Combine(OutputDirectory!, "oversized-owned.png");
            using (var stream = File.Create(oversized)) stream.SetLength(15 * 1024 * 1024 + 1);
            bad.SetStorageItems([await StorageFile.GetFileFromPathAsync(oversized)]);
            await shell.ImportImageAsync(bad.GetView());
            Check(vm.DraftImagePath == staged && Descendants(shell).OfType<TextBlock>().Any(t => t.Name == "ImageInputStatus" && t.Text.Contains("15 MB")),
                "oversized image reports the storage limit without replacing the draft");
            rpc.FailSend = true; Invoke("SendButton");
            await UntilAsync(() => rpc.Sent == 1 && !vm.IsSending);
            Check(vm.DraftImagePath == staged && vm.DraftText == "사진과 함께 보낼 문구 😊" && File.Exists(staged) && storage.DeletedImages == 1,
                "failed photo send retains the draft and removes the failed remote upload");
            rpc.FailSend = false; Invoke("SendButton");
            await UntilAsync(() => rpc.Sent == 2 && !vm.IsSending && vm.DraftImagePath is null);
            Check(storage.LastUploadedImage!.SequenceEqual(originalBytes) && rpc.LastChatBody!["body_text"] as string == "사진과 함께 보낼 문구 😊"
                && rpc.LastChatBody["media_file_name_text"] as string == "owned-photo.png",
                "native send uses the real image upload and chat payload with filename and caption");
            Check(vm.DraftText == "" && !File.Exists(staged) && File.Exists(file.Path),
                "successful send clears its draft snapshot while preserving the source photo");

            var rawFile = await (await file.GetParentAsync()).CreateFileAsync("owned-4k.bmp", CreationCollisionOption.ReplaceExisting);
            using (var stream = await rawFile.OpenAsync(FileAccessMode.ReadWrite))
            {
                var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.BmpEncoderId, stream);
                var pixels = new byte[3840 * 2160 * 4];
                for (var i = 0; i < pixels.Length; i += 4) { pixels[i] = 150; pixels[i + 1] = 100; pixels[i + 2] = 200; pixels[i + 3] = 255; }
                encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, 3840, 2160, 96, 96, pixels);
                await encoder.FlushAsync();
                Check(stream.Size > 15 * 1024 * 1024, "owned 4K screenshot fixture exceeds upload limit before PNG compression");
            }
            var raw = new DataPackage(); raw.SetBitmap(RandomAccessStreamReference.CreateFromFile(rawFile));
            await shell.ImportImageAsync(raw.GetView());
            Check(vm.DraftImagePath is { } normalized && new FileInfo(normalized).Length < 15 * 1024 * 1024,
                "raw 4K clipboard screenshot is accepted when its normalized PNG fits storage limit");
            Invoke("ClearImageButton");

            var current = Clipboard.GetContent();
            var backup = new DataPackage();
            foreach (var format in current.AvailableFormats)
            {
                if (format == StandardDataFormats.Bitmap)
                {
                    using var stream = await (await current.GetBitmapAsync()).OpenReadAsync();
                    savedBitmap = new InMemoryRandomAccessStream();
                    await RandomAccessStream.CopyAsync(stream, savedBitmap);
                    savedBitmap.Seek(0); backup.SetBitmap(RandomAccessStreamReference.CreateFromStream(savedBitmap));
                }
                else if (format == StandardDataFormats.StorageItems) backup.SetStorageItems(await current.GetStorageItemsAsync());
                else backup.SetData(format, await current.GetDataAsync(format));
            }
            originalClipboard = backup;
            var text = new DataPackage(); text.SetText("한글 텍스트 붙여넣기 😊"); Clipboard.SetContent(text);
            box.PasteFromClipboard();
            await UntilAsync(() => vm.DraftText == "한글 텍스트 붙여넣기 😊");
            Check(vm.DraftImagePath is null, "ordinary clipboard text still uses native text insertion");
            var bitmap = new DataPackage();
            bitmap.SetBitmap(RandomAccessStreamReference.CreateFromFile(file)); bitmap.SetText("사진의 텍스트 대체값");
            Clipboard.SetContent(bitmap); box.PasteFromClipboard();
            await UntilAsync(() => !vm.IsImportingImage && vm.DraftImagePath is not null);
            var pasted = vm.DraftImagePath;
            Check(vm.DraftImageName == "붙여넣은 사진.png" && vm.DraftText == "한글 텍스트 붙여넣기 😊",
                "native paste intercepts the clipboard bitmap without pasting its text alternative");
            await UntilAsync(() => preview.Source is BitmapImage { PixelWidth: 960, PixelHeight: 640 });
            Check(true, "clipboard bitmap is normalized to a decodable PNG attachment");
            Invoke("ClearImageButton");
            Check(vm.DraftImagePath is null && !File.Exists(pasted) && vm.DraftText == "한글 텍스트 붙여넣기 😊",
                "cancelling an attachment releases only the owned photo and retains text");

            var pureBitmap = new DataPackage(); pureBitmap.SetBitmap(RandomAccessStreamReference.CreateFromFile(file));
            Clipboard.SetContent(pureBitmap);
            await MessengerInputSmoke.ChordAsync(window, box, 0x11, 0x56);
            await UntilAsync(() => !vm.IsImportingImage && vm.DraftImagePath is not null);
            Check(vm.DraftImageName == "붙여넣은 사진.png", "actual Ctrl+V routes bitmap-only clipboard into the photo composer");
            Invoke("ClearImageButton");
            await MessengerInputSmoke.ChordAsync(window, box, 0x10, 0x2D);
            await UntilAsync(() => !vm.IsImportingImage && vm.DraftImagePath is not null);
            Check(vm.DraftImageName == "붙여넣은 사진.png", "actual Shift+Insert routes bitmap-only clipboard into the photo composer");
            Invoke("ClearImageButton");
            await MessengerInputSmoke.DropAsync(window, shell, file);
            await UntilAsync(() => !vm.IsImportingImage && vm.DraftImagePath is not null);
            Check(vm.DraftImageName == "owned-photo.png", "actual pointer drag and drop reaches the conversation attachment handler");
            Invoke("ClearImageButton");

            var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var delayed = new DataPackage();
            delayed.SetDataProvider(StandardDataFormats.Bitmap, async request =>
            {
                var deferral = request.GetDeferral(); started.SetResult();
                try { await gate.Task; request.SetData(RandomAccessStreamReference.CreateFromFile(file)); }
                finally { deferral.Complete(); }
            });
            var loading = shell.ImportImageAsync(delayed.GetView()); await started.Task;
            Check(!vm.CanSend && await vm.SendFromComposerAsync() == ChatSendOutcome.NoContent,
                "send waits for the pending image instead of sending an old draft");
            await shell.FocusRoomAsync("b"); gate.SetResult(); await loading;
            Check(vm.DraftImagePath is null && vm.DraftText == "" && !vm.IsImportingImage,
                "late image read cannot attach to a different room");
            await shell.FocusRoomAsync("a"); await shell.ImportImageAsync(data.GetView());
            var roomA = vm.DraftImagePath;
            await shell.FocusRoomAsync("b"); await shell.ImportImageAsync(data.GetView());
            var roomB = vm.DraftImagePath;
            await shell.FocusRoomAsync("a");
            Check(vm.DraftImagePath == roomA && File.Exists(roomA) && File.Exists(roomB),
                "unsent attachment drafts stay with their own room");
            await shell.DetachAsync();
            Check(!File.Exists(roomA) && !File.Exists(roomB) && preview.Source is null,
                "account detach releases all owned unsent snapshots and their preview");
        }
        finally
        {
            try { if (originalClipboard is not null) { Clipboard.SetContent(originalClipboard); Clipboard.Flush(); } }
            finally { savedBitmap?.Dispose(); await shell.DetachAsync(); window.CloseForQuit(); }
        }
    }
}
#endif
