using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using global::Windows.ApplicationModel.DataTransfer;
using global::Windows.Storage;

namespace Ping.Windows.App.History;

public sealed partial class HistoryWindow
{
    private int imageInputGeneration;
    private string? imageInputRoom;
    private readonly Dictionary<string, ImportedImage> importedImages = new(StringComparer.OrdinalIgnoreCase);

    private void InitializeImageInput()
    {
        imageInputRoom = viewModel.SelectedRoom?.Id;
        viewModel.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(HistoryViewModel.SelectedRoom) && imageInputRoom != viewModel.SelectedRoom?.Id)
            {
                imageInputRoom = viewModel.SelectedRoom?.Id;
                imageInputGeneration++;
                viewModel.IsImportingImage = false;
                ImageDropOverlay.Visibility = Visibility.Collapsed;
                ImageInputStatus.Visibility = Visibility.Collapsed;
            }
            if (args.PropertyName == nameof(HistoryViewModel.DraftImagePath))
            {
                DraftPhotoImage.Source = !detached && viewModel.DraftImagePath is { } path ? new BitmapImage(new Uri(path)) : null;
                ReleaseUnusedImages();
            }
        };
    }

    private void Conversation_DragOver(object sender, DragEventArgs args)
    {
        var accept = !detached && viewModel.CanCompose && ImageAttachmentReader.Supports(args.DataView);
        args.AcceptedOperation = accept ? DataPackageOperation.Copy : DataPackageOperation.None;
        if (!accept) return;
        args.Handled = true;
        args.DragUIOverride.Caption = "사진 첨부";
        ImageDropOverlay.Visibility = Visibility.Visible;
    }
    private void Conversation_DragLeave(object sender, DragEventArgs args) => ImageDropOverlay.Visibility = Visibility.Collapsed;
    private async void Conversation_Drop(object sender, DragEventArgs args)
    {
        ImageDropOverlay.Visibility = Visibility.Collapsed;
        if (!ImageAttachmentReader.Supports(args.DataView)) return;
        args.Handled = true;
        var deferral = args.GetDeferral();
        try { await ImportImageAsync(args.DataView); }
        finally { deferral.Complete(); }
    }
    private async void ChatBox_Paste(object sender, TextControlPasteEventArgs args)
    {
        if (!TryGetClipboardImage(out var data)) return;
        args.Handled = true;
        await ImportImageAsync(data!);
    }
    private bool TryGetClipboardImage(out DataPackageView? data)
    {
        data = null;
        try { data = Clipboard.GetContent(); return ImageAttachmentReader.Supports(data); }
        catch { ShowImageInputStatus("클립보드 사진을 읽을 수 없어요. 다시 붙여넣어 주세요."); return false; }
    }
    private async void PastePhoto_Click(object sender, RoutedEventArgs args)
    {
        if (TryGetClipboardImage(out var data)) await ImportImageAsync(data!);
        else ShowImageInputStatus("복사한 사진이 없어요. 사진을 복사한 뒤 붙여넣어 주세요.");
    }

    public Task ImportImageAsync(DataPackageView data) => ReadImageInputAsync(token => ImageAttachmentReader.ReadAsync(data, token));
    private Task ImportImageFileAsync(StorageFile file) => ReadImageInputAsync(token => ImageAttachmentReader.ReadFileAsync(file, token));
    private async Task ReadImageInputAsync(Func<CancellationToken, Task<ImportedImage>> read)
    {
        if (detached || !viewModel.CanCompose) return;
        var generation = ++imageInputGeneration;
        var roomId = viewModel.SelectedRoom!.Id;
        viewModel.IsImportingImage = true;
        ShowImageInputStatus("사진을 불러오는 중…");
        ImportedImage? image = null;
        try
        {
            image = await read(roomLifetime.Token);
            if (detached || generation != imageInputGeneration || viewModel.SelectedRoom?.Id != roomId) return;
            importedImages.Add(image.Path, image);
            viewModel.DraftImagePath = image.Path;
            image = null;
            ImageInputStatus.Visibility = Visibility.Collapsed;
            ChatBox.Focus(FocusState.Programmatic);
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            if (!detached && generation == imageInputGeneration)
                ShowImageInputStatus(ex is InvalidOperationException ? ex.Message : "사진을 읽을 수 없어요. 다른 사진으로 다시 시도해 주세요.");
        }
        finally
        {
            image?.Dispose();
            if (generation == imageInputGeneration) viewModel.IsImportingImage = false;
            ReleaseUnusedImages();
        }
    }
    private void ShowImageInputStatus(string text)
    {
        if (detached) return;
        ImageInputStatus.Text = text;
        ImageInputStatus.Visibility = Visibility.Visible;
    }
    private void ReleaseUnusedImages()
    {
        var keep = viewModel.ImageDraftPaths.ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var pair in importedImages.ToArray())
        {
            if ((!detached || viewModel.IsSending) && keep.Contains(pair.Key)) continue;
            importedImages.Remove(pair.Key);
            pair.Value.Dispose();
        }
    }
}
