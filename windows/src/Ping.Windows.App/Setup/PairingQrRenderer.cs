using Ping.Windows.Core.Backend;
using QRCoder;

namespace Ping.Windows.App.Setup;

public sealed record PairingQrImage(byte[] Png, string UserId, DateTimeOffset ExpiresAt)
{
    public override string ToString() => "Ping pairing QR (session redacted)";
}

public static class PairingQrRenderer
{
    public static PairingQrImage Render(DeviceHandoffPayload payload)
    {
        using var generator = new QRCodeGenerator();
        using var code = generator.CreateQrCode(payload.EncodeUtf8(), QRCodeGenerator.ECCLevel.L);
        using var image = new PngByteQRCode(code);
        return new(image.GetGraphic(4), payload.UserId, payload.ExpiresAt);
    }
}
