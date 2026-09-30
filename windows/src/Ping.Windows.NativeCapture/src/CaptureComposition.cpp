#include "PingCaptureEngine.h"
#include "CapturePixelView.h"
#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace
{
    bool ValidPixels(Ping::Windows::NativeCapture::CaptureSize size, std::uint32_t pitch,
        std::vector<std::uint8_t> const& bytes)
    {
        return size.Width > 0 && size.Height > 0 && size.Width <= 32768 && size.Height <= 32768
            && pitch >= static_cast<size_t>(size.Width) * 4
            && bytes.size() >= static_cast<size_t>(pitch) * size.Height;
    }

    bool ValidOutput(Ping::Windows::NativeCapture::CaptureSize size)
    {
        return size.Width > 0 && size.Height > 0 && size.Width <= 1920 && size.Height <= 1920;
    }

    double Center(double value, double inset)
    {
        return std::clamp(std::isfinite(value) ? value : .5, inset, 1 - inset);
    }
}

namespace Ping::Windows::NativeCapture
{
    CaptureCrop ComputeCaptureCrop(CaptureSize sourceSize, CaptureViewport viewport)
    {
        if (sourceSize.Width <= 0 || sourceSize.Height <= 0) return {};
        auto zoom = std::clamp(std::isfinite(viewport.Zoom) ? viewport.Zoom : 1, 1.0, 4.0);
        auto inset = .5 / zoom;
        int width = std::max(1, static_cast<int>(std::floor(sourceSize.Width / zoom)));
        int height = std::max(1, static_cast<int>(std::floor(sourceSize.Height / zoom)));
        int x = static_cast<int>(std::lround(Center(viewport.CenterX, inset) * sourceSize.Width - width / 2.0));
        int y = static_cast<int>(std::lround(Center(viewport.CenterY, inset) * sourceSize.Height - height / 2.0));
        return {std::clamp(x, 0, sourceSize.Width - width), std::clamp(y, 0, sourceSize.Height - height), width, height};
    }

    int CropScreenFrame(MonitorCaptureResult const& source, CaptureViewport viewport,
        CaptureSize outputSize, MonitorCaptureResult& output)
    {
        if (&source == &output) return PingCaptureCaptureFailure;
        output = {};
        if (!ValidPixels(source.SourceSize, source.RowPitch, source.BgraPixels) || !ValidOutput(outputSize)
            || source.RowPitch > static_cast<std::uint32_t>(std::numeric_limits<std::int32_t>::max()))
            return PingCaptureCaptureFailure;
        auto crop = ComputeCaptureCrop(source.SourceSize, viewport);
        CapturePixelView view{source.BgraPixels.data(), source.BgraPixels.size(), 0,
            static_cast<std::int32_t>(source.RowPitch), source.SourceSize};
        auto result = ResizeCapturePixels(view, crop, outputSize, output.BgraPixels, output.RowPitch);
        if (result == PingCaptureSuccess) { output.SourceSize = outputSize; output.Device = source.Device; }
        return result;
    }

    int ComposeScreenFaceFrame(OutputLayout const& layout, MonitorCaptureResult const& screen,
        CameraFrameResult const& camera, CaptureViewport viewport, std::vector<std::uint8_t>& output)
    {
        if (&output == &screen.BgraPixels || &output == &camera.BgraPixels) return PingCaptureCaptureFailure;
        output.clear();
        if (!ValidOutput({layout.Width, layout.Height}) || layout.FaceDiameter <= 0
            || layout.FaceDiameter > std::min(layout.Width, layout.Height)
            || layout.FaceX < 0 || layout.FaceY < 0
            || layout.FaceX > layout.Width - layout.FaceDiameter || layout.FaceY > layout.Height - layout.FaceDiameter)
            return PingCaptureCaptureFailure;
        if (!ValidPixels(camera.SourceSize, camera.RowPitch, camera.BgraPixels)) return PingCaptureNoCamera;
        MonitorCaptureResult cropped{};
        int result = CropScreenFrame(screen, viewport, {layout.Width, layout.Height}, cropped);
        if (result != PingCaptureSuccess) return result;
        output = std::move(cropped.BgraPixels);

        int side = std::min(camera.SourceSize.Width, camera.SourceSize.Height);
        int originX = (camera.SourceSize.Width - side) / 2;
        int originY = (camera.SourceSize.Height - side) / 2;
        double radius = layout.FaceDiameter / 2.0;
        for (int y = 0; y < layout.FaceDiameter; ++y)
            for (int x = 0; x < layout.FaceDiameter; ++x)
            {
                double dx = x + .5 - radius;
                double dy = y + .5 - radius;
                double alpha = std::clamp(radius - std::sqrt(dx * dx + dy * dy), 0.0, 1.0);
                if (alpha <= 0) continue;
                int cameraX = originX + static_cast<int>(static_cast<long long>(x) * side / layout.FaceDiameter);
                int cameraY = originY + static_cast<int>(static_cast<long long>(y) * side / layout.FaceDiameter);
                auto from = camera.BgraPixels.data() + static_cast<size_t>(cameraY) * camera.RowPitch + cameraX * 4;
                auto to = output.data() + (static_cast<size_t>(layout.FaceY + y) * layout.Width + layout.FaceX + x) * 4;
                for (int channel = 0; channel < 3; ++channel)
                    to[channel] = static_cast<std::uint8_t>(std::lround(alpha * from[channel] + (1 - alpha) * to[channel]));
                to[3] = 0xff;
            }
        return PingCaptureSuccess;
    }
}
