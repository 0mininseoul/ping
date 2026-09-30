#include "CapturePixelView.h"
#include <algorithm>
#include <limits>

namespace Ping::Windows::NativeCapture
{
    int ResizeCapturePixels(CapturePixelView const& source, CaptureCrop crop, CaptureSize outputSize,
        std::vector<std::uint8_t>& pixels, std::uint32_t& outputPitch)
    {
        auto size = source.SourceSize;
        if (!source.Data || size.Width <= 0 || size.Height <= 0 || size.Width > 32768 || size.Height > 32768
            || outputSize.Width <= 0 || outputSize.Height <= 0 || outputSize.Width > 1920 || outputSize.Height > 1920
            || crop.X < 0 || crop.Y < 0 || crop.Width <= 0 || crop.Height <= 0 || crop.Width > size.Width || crop.Height > size.Height
            || crop.X > size.Width - crop.Width || crop.Y > size.Height - crop.Height
            || source.FirstRowOffset > static_cast<size_t>(std::numeric_limits<std::ptrdiff_t>::max()))
            return PingCaptureCaptureFailure;
        auto stride = static_cast<std::int64_t>(source.Stride);
        auto rowBytes = static_cast<size_t>(size.Width) * 4;
        if (stride == 0 || static_cast<size_t>(stride < 0 ? -stride : stride) < rowBytes) return PingCaptureCaptureFailure;
        auto first = static_cast<std::int64_t>(source.FirstRowOffset);
        auto displacement = static_cast<std::int64_t>(size.Height - 1) * stride;
        if ((displacement > 0 && first > std::numeric_limits<std::int64_t>::max() - displacement)
            || (displacement < 0 && first < -displacement)) return PingCaptureCaptureFailure;
        auto last = first + displacement;
        auto maxRow = static_cast<size_t>(std::max(first, last));
        if (maxRow > source.ByteLength || rowBytes > source.ByteLength - maxRow) return PingCaptureCaptureFailure;

        auto sourceAddress = reinterpret_cast<std::uintptr_t>(source.Data);
        auto outputAddress = reinterpret_cast<std::uintptr_t>(pixels.data());
        if (source.ByteLength > std::numeric_limits<std::uintptr_t>::max() - sourceAddress
            || pixels.capacity() > std::numeric_limits<std::uintptr_t>::max() - outputAddress)
            return PingCaptureCaptureFailure;
        if (pixels.capacity() != 0 && outputAddress < sourceAddress + source.ByteLength
            && sourceAddress < outputAddress + pixels.capacity()) return PingCaptureCaptureFailure;

        outputPitch = static_cast<std::uint32_t>(outputSize.Width) * 4;
        pixels.resize(static_cast<size_t>(outputPitch) * outputSize.Height);
        for (int y = 0; y < outputSize.Height; ++y)
        {
            auto sourceY = crop.Y + static_cast<int>(static_cast<std::int64_t>(y) * crop.Height / outputSize.Height);
            auto row = source.Data + static_cast<std::ptrdiff_t>(first + static_cast<std::int64_t>(sourceY) * stride);
            for (int x = 0; x < outputSize.Width; ++x)
            {
                auto sourceX = crop.X + static_cast<int>(static_cast<std::int64_t>(x) * crop.Width / outputSize.Width);
                auto input = row + static_cast<size_t>(sourceX) * 4;
                auto output = pixels.data() + static_cast<size_t>(y) * outputPitch + x * 4;
                output[0] = input[0]; output[1] = input[1]; output[2] = input[2]; output[3] = 255;
            }
        }
        return PingCaptureSuccess;
    }
}
