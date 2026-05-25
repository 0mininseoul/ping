namespace Ping.Windows.App.Setup;

public interface IClipboardWriter
{
    Task<bool> TrySetTextAsync(string text, CancellationToken cancellationToken = default);
}

public sealed class ClipboardWriter : IClipboardWriter
{
    public Task<bool> TrySetTextAsync(string text, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
#if NET8_0_WINDOWS || NET9_0_WINDOWS || NET10_0_WINDOWS
        try
        {
            var package = new global::Windows.ApplicationModel.DataTransfer.DataPackage();
            package.SetText(text);
            global::Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
            global::Windows.ApplicationModel.DataTransfer.Clipboard.Flush();
            return Task.FromResult(true);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return Task.FromResult(false);
        }
#else
        return Task.FromResult(false);
#endif
    }
}
