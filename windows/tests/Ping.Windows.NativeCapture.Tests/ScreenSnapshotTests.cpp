#include "PingCaptureEngine.h"
#include "ScreenFrameContract.h"
#include <fstream>
#include <string>

using namespace Ping::Windows::NativeCapture;
extern int FixturePreviewMode;
extern CaptureViewport FixturePreviewViewport;

void ScreenSnapshotChecks(wchar_t const* directory, void (*check)(bool, char const*))
{
    FixturePreviewMode = 1;
    auto path = std::wstring(directory) + L"\\selected-preview.bmp";
    double aspect = 0;
    auto result = PingCapture_WriteScreenPreviewBmpV2(path.c_str(), 0, 2, .6, .4, nullptr, &aspect);
    check(result == PingCaptureSuccess && aspect == 2 && FixturePreviewViewport.Zoom == 2
        && FixturePreviewViewport.CenterX == .6 && FixturePreviewViewport.CenterY == .4,
        "preview entry uses viewport-aware bounded snapshot source");
    std::ifstream file(path, std::ios::binary);
    BITMAPFILEHEADER header{}; BITMAPINFOHEADER info{};
    file.read(reinterpret_cast<char*>(&header), sizeof(header)); file.read(reinterpret_cast<char*>(&info), sizeof(info));
    std::uint8_t pixel[4]{}; file.read(reinterpret_cast<char*>(pixel), 4);
    auto crop = ComputeCaptureCrop({8, 4}, {2, .6, .4});
    check(header.bfType == 0x4D42 && info.biWidth == 8 && info.biHeight == -4
        && pixel[0] == crop.X && pixel[1] == crop.Y && pixel[3] == 255,
        "BMP stores normalized topdown preview without applying selected crop twice");
    file.close(); FixturePreviewMode = 2; path = std::wstring(directory) + L"\\cancelled-preview.bmp";
    result = PingCapture_WriteScreenPreviewBmpV2(path.c_str(), 0, 1, .5, .5, nullptr, &aspect);
    check(result == PingCaptureCancelled && GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES,
        "snapshot cancellation propagates from owned source without preview file");
    FixturePreviewMode = 0;

    D3D11_TEXTURE2D_DESC texture{};
    texture.Width = 1920; texture.Height = 1080; texture.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    texture.MipLevels = 1; texture.ArraySize = 1; texture.SampleDesc.Count = 1;
    check(ValidateScreenTexture(texture, {1920, 1080}, {1920, 1080}), "WGC accepts matching BGRA texture and content size");
    check(!ValidateScreenTexture(texture, {1920, 1080}, {1080, 1920}), "display resize fails before mapped row reads");
    texture.Width = 1919;
    check(!ValidateScreenTexture(texture, {1920, 1080}, {1920, 1080}), "truncated WGC texture cannot back full content rows");
    texture.Width = 1920; texture.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    check(!ValidateScreenTexture(texture, {1920, 1080}, {1920, 1080}), "different texture format cannot be interpreted as BGRA");
    texture.Format = DXGI_FORMAT_B8G8R8A8_UNORM; texture.ArraySize = 2;
    check(!ValidateScreenTexture(texture, {1920, 1080}, {1920, 1080}), "unexpected WGC texture array is rejected");
    texture.ArraySize = 1;
    auto cached = texture; texture.Width += 16;
    check(!SameScreenTextureStorage(cached, texture), "changed WGC texture storage recreates staging instead of invalid CopyResource");
    check(SameScreenTextureStorage(texture, texture), "matching WGC texture storage can reuse staging");
}
