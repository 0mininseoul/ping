#pragma once
#include "PingCaptureEngine.h"

namespace Ping::Windows::NativeCapture
{
    inline bool ValidateScreenTexture(D3D11_TEXTURE2D_DESC const& texture, CaptureSize content, CaptureSize expected)
    {
        return content.Width > 0 && content.Height > 0 && content.Width <= 32768 && content.Height <= 32768
            && content.Width == expected.Width && content.Height == expected.Height
            && texture.Width >= static_cast<UINT>(content.Width) && texture.Height >= static_cast<UINT>(content.Height)
            && texture.Format == DXGI_FORMAT_B8G8R8A8_UNORM && texture.SampleDesc.Count == 1
            && texture.MipLevels == 1 && texture.ArraySize == 1;
    }
    inline bool SameScreenTextureStorage(D3D11_TEXTURE2D_DESC const& left, D3D11_TEXTURE2D_DESC const& right)
    {
        return left.Width == right.Width && left.Height == right.Height && left.Format == right.Format
            && left.MipLevels == right.MipLevels && left.ArraySize == right.ArraySize
            && left.SampleDesc.Count == right.SampleDesc.Count && left.SampleDesc.Quality == right.SampleDesc.Quality;
    }
}
