using System.Runtime.InteropServices.WindowsRuntime;
using global::Windows.ApplicationModel.DataTransfer;
using global::Windows.Graphics.Imaging;
using global::Windows.Storage;

namespace Ping.Windows.App.History;

internal sealed class ImportedImage(string path) : IDisposable
{
    public string Path { get; } = path;
    public void Dispose()
    {
        try { File.Delete(Path); Directory.Delete(System.IO.Path.GetDirectoryName(Path)!); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}

internal static class ImageAttachmentReader
{
    private const ulong MaxBytes = 15 * 1024 * 1024;
    public static bool Supports(DataPackageView data) =>
        data.Contains(StandardDataFormats.StorageItems) || data.Contains(StandardDataFormats.Bitmap);

    public static async Task<ImportedImage> ReadAsync(DataPackageView data, CancellationToken token)
    {
        if (data.Contains(StandardDataFormats.StorageItems))
        {
            var items = await data.GetStorageItemsAsync().AsTask(token);
            if (items.Count != 1 || items[0] is not StorageFile file)
                throw new InvalidOperationException("사진을 한 장씩 첨부해 주세요.");
            return await ReadFileAsync(file, token);
        }
        if (!data.Contains(StandardDataFormats.Bitmap)) throw new InvalidOperationException("사진을 첨부해 주세요.");
        var reference = await data.GetBitmapAsync().AsTask(token);
        using var source = await reference.OpenReadAsync().AsTask(token);
        if (source.Size == 0 || source.Size > 256UL * 1024 * 1024)
            throw new InvalidOperationException("클립보드 사진 크기를 줄인 뒤 다시 붙여넣어 주세요.");
        var decoder = await BitmapDecoder.CreateAsync(source).AsTask(token);
        CheckDimensions(decoder);
        var image = Create("붙여넣은 사진.png");
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(image.Path).AsTask(token);
            using var target = await file.OpenAsync(FileAccessMode.ReadWrite).AsTask(token);
            using var bitmap = await decoder.GetSoftwareBitmapAsync().AsTask(token);
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, target).AsTask(token);
            encoder.SetSoftwareBitmap(bitmap);
            await encoder.FlushAsync().AsTask(token);
            CheckSize(target.Size);
            token.ThrowIfCancellationRequested();
            return image;
        }
        catch { image.Dispose(); throw; }
    }

    public static async Task<ImportedImage> ReadFileAsync(StorageFile file, CancellationToken token)
    {
        if (file.FileType.ToLowerInvariant() is not (".jpg" or ".jpeg" or ".png" or ".heic" or ".heif" or ".gif" or ".webp"))
            throw new InvalidOperationException("JPEG, PNG, HEIC, HEIF, GIF, WebP 사진을 첨부해 주세요.");
        using var source = await file.OpenReadAsync().AsTask(token);
        CheckSize(source.Size);
        var image = Create(file.Name);
        try
        {
            using (var target = File.OpenWrite(image.Path))
                await source.AsStreamForRead().CopyToAsync(target, token);
            var copy = await StorageFile.GetFileFromPathAsync(image.Path).AsTask(token);
            using var stream = await copy.OpenReadAsync().AsTask(token);
            CheckSize(stream.Size);
            CheckDimensions(await BitmapDecoder.CreateAsync(stream).AsTask(token));
            token.ThrowIfCancellationRequested();
            return image;
        }
        catch { image.Dispose(); throw; }
    }

    private static ImportedImage Create(string name)
    {
        var directory = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "PingWindowsChatImages", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var path = System.IO.Path.Combine(directory, System.IO.Path.GetFileName(name));
        File.WriteAllBytes(path, []);
        return new(path);
    }
    private static void CheckSize(ulong size)
    {
        if (size == 0 || size > MaxBytes) throw new InvalidOperationException("사진은 15 MB 이하의 파일로 첨부해 주세요.");
    }
    private static void CheckDimensions(BitmapDecoder decoder)
    {
        if ((ulong)decoder.PixelWidth * decoder.PixelHeight > 64_000_000)
            throw new InvalidOperationException("사진 크기를 줄인 뒤 다시 첨부해 주세요.");
    }
}
