#pragma once
#include "PingCaptureEngine.h"

namespace Ping::Windows::NativeCapture
{
    struct CapturePixelView
    {
        std::uint8_t const* Data;
        size_t ByteLength;
        size_t FirstRowOffset;
        std::int32_t Stride;
        CaptureSize SourceSize;
    };

    int ResizeCapturePixels(CapturePixelView const& source, CaptureCrop crop, CaptureSize outputSize,
        std::vector<std::uint8_t>& pixels, std::uint32_t& outputPitch);
}
