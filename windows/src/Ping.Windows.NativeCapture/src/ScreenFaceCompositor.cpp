#include "PingCaptureEngine.h"

#include <algorithm>
#include <cmath>

namespace
{
    constexpr int MaxOutputLongSide = 1920;
    constexpr double DefaultFaceDiameterRatio = 0.32;
    constexpr double DefaultPaddingRatio = 0.045;

    double SanitizeRatio(double value)
    {
        if (!std::isfinite(value) || value <= 0)
        {
            return DefaultFaceDiameterRatio;
        }

        return std::clamp(value, 0.12, 0.60);
    }
}

namespace Ping::Windows::NativeCapture
{
    OutputLayout CreateScreenFaceLayout(CaptureSize sourceSize, double faceDiameterRatio, int maximumLongSide)
    {
        if (sourceSize.Width <= 0 || sourceSize.Height <= 0)
        {
            return { 0, 0, 0, 0, 0, 1 };
        }

        maximumLongSide = std::clamp(maximumLongSide, 2, MaxOutputLongSide);
        double scale = std::min(1.0, static_cast<double>(maximumLongSide) / std::max(sourceSize.Width, sourceSize.Height));
        auto evenDimension = [scale](int source)
        {
            auto half = source * scale / 2;
            return std::max(2, static_cast<int>(scale < 1 ? std::round(half) : std::floor(half)) * 2);
        };
        int outputWidth = evenDimension(sourceSize.Width);
        int outputHeight = evenDimension(sourceSize.Height);

        int shortestSide = std::min(outputWidth, outputHeight);
        int faceDiameter = std::max(1, static_cast<int>(std::lround(shortestSide * SanitizeRatio(faceDiameterRatio))));
        int margin = std::max(0, static_cast<int>(std::lround(shortestSide * DefaultPaddingRatio)));
        int faceX = std::max(0, outputWidth - faceDiameter - margin);
        int faceY = std::max(0, outputHeight - faceDiameter - margin);

        return
        {
            outputWidth,
            outputHeight,
            faceDiameter,
            faceX,
            faceY,
            static_cast<double>(outputWidth) / static_cast<double>(outputHeight)
        };
    }
}
