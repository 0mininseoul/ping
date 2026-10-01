#if PING_UI_SMOKE
using System.Net;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Ping.Windows.App.Setup;
using Ping.Windows.Core.Backend;

namespace Ping.Windows.App.Diagnostics;

internal static class DevicePairingSmoke
{
    private static readonly string Access = "fixture-access." + new string('a', 720);
    private static readonly string PublicKey = "fixture-public." + new string('p', 200);
    internal static async Task<PairingQrImage> CreateAsync(string output, CancellationToken token)
    {
        var root = Path.Combine(output, "pairing-fixture"); Directory.CreateDirectory(root);
        var config = Path.Combine(root, "config.json");
        await File.WriteAllTextAsync(config, JsonSerializer.Serialize(new { url = "https://example.supabase.co", anonKey = PublicKey }), token);
        using var http = new HttpClient(new FakeAuth());
        using var client = new SupabaseClient(http, config, Path.Combine(root, "session.json"));
        return PairingQrRenderer.Render(await client.ExportDeviceHandoffAsync(token));
    }
    internal static async Task VerifyAsync(Image image, byte[] png, Action<bool, string> check)
    {
        using var stream = new global::Windows.Storage.Streams.InMemoryRandomAccessStream();
        await stream.WriteAsync(png.AsBuffer()); stream.Seek(0);
        var decoder = await global::Windows.Graphics.Imaging.BitmapDecoder.CreateAsync(stream);
        var originalPixels = (await decoder.GetPixelDataAsync(global::Windows.Graphics.Imaging.BitmapPixelFormat.Bgra8,
            global::Windows.Graphics.Imaging.BitmapAlphaMode.Straight, new(), global::Windows.Graphics.Imaging.ExifOrientationMode.IgnoreExifOrientation,
            global::Windows.Graphics.Imaging.ColorManagementMode.DoNotColorManage)).DetachPixelData();
        var original = Reader().Decode(originalPixels, (int)decoder.PixelWidth, (int)decoder.PixelHeight, ZXing.RGBLuminanceSource.BitmapFormat.BGRA32);
        check(original is not null, "synthetic pairing PNG decodes before display");
        var bitmap = new RenderTargetBitmap(); await bitmap.RenderAsync(image);
        var pixels = (await bitmap.GetPixelsAsync()).ToArray();
        var decoded = Reader().Decode(pixels, bitmap.PixelWidth, bitmap.PixelHeight,
            ZXing.RGBLuminanceSource.BitmapFormat.BGRA32);
        check(decoded is not null, "actual displayed synthetic pairing QR is decodable");
        using var json = JsonDocument.Parse(decoded!.Text);
        var payload = json.RootElement;
        check(payload.EnumerateObject().Count() == 6 && payload.GetProperty("accessToken").GetString() == Access
            && payload.GetProperty("anonKey").GetString() == PublicKey && payload.GetProperty("refreshToken").GetString() == "fixture-refresh"
            && payload.GetProperty("userId").GetString() == "me" && payload.GetProperty("url").GetString() == "https://example.supabase.co/"
            && payload.GetProperty("expiresAt").GetDateTimeOffset() > DateTimeOffset.UtcNow,
            "decoded displayed QR retains Mac handoff fields and ISO8601 expiry");
    }
    private static ZXing.BarcodeReaderGeneric Reader() => new() { AutoRotate = true,
        Options = new ZXing.Common.DecodingOptions { TryHarder = true, PossibleFormats = [ZXing.BarcodeFormat.QR_CODE] } };
    private sealed class FakeAuth : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new
            { access_token = Access, refresh_token = "fixture-refresh", expires_in = 3600, user = new { id = "me" } })) });
    }
}
#endif
