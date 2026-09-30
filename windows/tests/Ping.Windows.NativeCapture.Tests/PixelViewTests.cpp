#include "CapturePixelView.h"
#include <limits>

using namespace Ping::Windows::NativeCapture;

void PixelViewChecks(void (*check)(bool, char const*))
{
    std::vector<std::uint8_t> source(3 * 20, 0xee);
    for (int y = 0; y < 3; ++y)
        for (int x = 0; x < 4; ++x)
        {
            auto pixel = static_cast<size_t>(2 - y) * 20 + x * 4;
            source[pixel] = static_cast<std::uint8_t>(x); source[pixel + 1] = static_cast<std::uint8_t>(y);
            source[pixel + 2] = 50; source[pixel + 3] = 12;
        }
    CapturePixelView view{source.data(), source.size(), 40, -20, {4, 3}};
    std::vector<std::uint8_t> output;
    std::uint32_t pitch = 0;
    check(ResizeCapturePixels(view, {0, 0, 4, 3}, {4, 3}, output, pitch) == PingCaptureSuccess,
        "source view normalizes negative stride and padded rows without fullsource copy");
    check(pitch == 16 && output.size() == 48 && output[1] == 0 && output[33] == 2 && output[3] == 255,
        "normalized frame is packed topdown opaque BGRA");
    check(ResizeCapturePixels(view, {1, 1, 2, 2}, {2, 2}, output, pitch) == PingCaptureSuccess
        && output[0] == 1 && output[1] == 1 && output[12] == 2 && output[13] == 2,
        "selected region resizes directly from signedstride source");
    view.FirstRowOffset = 39;
    check(ResizeCapturePixels(view, {0, 0, 4, 3}, {4, 3}, output, pitch) == PingCaptureCaptureFailure,
        "negative stride cannot read before buffer start");
    view.FirstRowOffset = 40; view.ByteLength = 55;
    check(ResizeCapturePixels(view, {0, 0, 4, 3}, {4, 3}, output, pitch) == PingCaptureCaptureFailure,
        "truncated firstrow fails before any source read");
    view.ByteLength = source.size(); view.Stride = std::numeric_limits<std::int32_t>::min();
    check(ResizeCapturePixels(view, {0, 0, 4, 3}, {4, 3}, output, pitch) == PingCaptureCaptureFailure,
        "extreme signed stride fails without overflow");
    view.Stride = -20;
    check(ResizeCapturePixels(view, {3, 0, 2, 3}, {4, 3}, output, pitch) == PingCaptureCaptureFailure,
        "crop cannot extend beyond resized source");
    check(ResizeCapturePixels(view, {0, 0, 4, 3}, {1921, 2}, output, pitch) == PingCaptureCaptureFailure,
        "normalization limits allocation independently of source resolution");
    check(ResizeCapturePixels(view, {0, 0, 4, 3}, {4, 3}, source, pitch) == PingCaptureCaptureFailure,
        "source and output alias cannot invalidate mapped pixels");
    std::vector<std::uint8_t> black(4 * 3 * 4, 0);
    view = {black.data(), black.size(), 0, 16, {4, 3}};
    check(ResizeCapturePixels(view, {0, 0, 4, 3}, {4, 3}, output, pitch) == PingCaptureSuccess && output[0] == 0,
        "valid black input remains valid media");
}
