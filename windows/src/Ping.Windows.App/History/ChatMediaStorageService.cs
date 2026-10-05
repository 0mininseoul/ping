using System.Runtime.InteropServices.WindowsRuntime;
using Ping.Windows.Core.Backend;
using global::Windows.Graphics.Imaging;
using global::Windows.Storage;

namespace Ping.Windows.App.History;

internal sealed class ChatMediaStorageService(IChatMediaStorageService storage) : IChatMediaStorageService
{
    public async Task<ChatImageUpload> UploadChatImageAsync(string localImagePath, string senderUid, string messageId, CancellationToken cancellationToken = default)
    {
        var file = await StorageFile.GetFileFromPathAsync(localImagePath).AsTask(cancellationToken);
        using var stream = await file.OpenReadAsync().AsTask(cancellationToken);
        var decoder = await BitmapDecoder.CreateAsync(stream).AsTask(cancellationToken);
        var width = checked((int)decoder.OrientedPixelWidth);
        var height = checked((int)decoder.OrientedPixelHeight);
        if (width <= 0 || height <= 0 || (long)width * height > 64_000_000)
            throw new InvalidOperationException("사진 크기를 줄인 뒤 다시 첨부해 주세요.");
        var uploaded = await storage.UploadChatImageAsync(localImagePath, senderUid, messageId, cancellationToken);
        return uploaded with { Width = width, Height = height };
    }
    public Task<string> DownloadChatMediaAsync(string remotePath, string fileExtension, CancellationToken cancellationToken = default) =>
        storage.DownloadChatMediaAsync(remotePath, fileExtension, cancellationToken);
    public Task DeleteChatMediaAsync(string remotePath, CancellationToken cancellationToken = default) =>
        storage.DeleteChatMediaAsync(remotePath, cancellationToken);
}
