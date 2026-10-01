#include "PingCaptureEngine.h"
#include <cmath>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <atomic>

using namespace Ping::Windows::NativeCapture;
extern std::atomic<int> FixtureSourceStarts;
void EncoderChecks(wchar_t const* directory, void (*check)(bool, char const*));
void RecordingStreamChecks(wchar_t const* directory, void (*check)(bool, char const*));
void PixelViewChecks(void (*check)(bool, char const*));
void LiveRecordingChecks(void (*check)(bool, char const*));
void LiveEntryChecks(wchar_t const* directory, void (*check)(bool, char const*));
void MicrophonePacketChecks(void (*check)(bool, char const*));
void ScreenSnapshotChecks(wchar_t const* directory, void (*check)(bool, char const*));
void CameraSampleChecks(void (*check)(bool, char const*));

namespace
{
    int checks = 0;
    void Check(bool condition, char const* label)
    {
        if (!condition) throw std::runtime_error(label);
        ++checks;
        std::cout << "PASS " << label << '\n';
    }

    MonitorCaptureResult Grid(int width, int height, int padding = 0)
    {
        MonitorCaptureResult result{};
        result.SourceSize = {width, height};
        result.RowPitch = width * 4 + padding;
        result.BgraPixels.resize(static_cast<size_t>(result.RowPitch) * height, 0xee);
        for (int y = 0; y < height; ++y)
            for (int x = 0; x < width; ++x)
            {
                auto i = static_cast<size_t>(y) * result.RowPitch + x * 4;
                result.BgraPixels[i] = static_cast<std::uint8_t>(x);
                result.BgraPixels[i + 1] = static_cast<std::uint8_t>(y);
                result.BgraPixels[i + 2] = 0x20;
                result.BgraPixels[i + 3] = 0xff;
            }
        return result;
    }

    void CropChecks()
    {
        auto full = ComputeCaptureCrop({8, 6}, {});
        Check(full.X == 0 && full.Y == 0 && full.Width == 8 && full.Height == 6, "full viewport includes every source pixel");
        auto center = ComputeCaptureCrop({8, 6}, {2, .5, .5});
        Check(center.X == 2 && center.Y == 2 && center.Width == 4 && center.Height == 3, "center zoom rounds within source bounds");
        auto edge = ComputeCaptureCrop({1920, 1080}, {4, -1, 2});
        Check(edge.X == 0 && edge.Y == 810 && edge.Width == 480 && edge.Height == 270, "zoom edge crop remains within source");
        auto nan = std::numeric_limits<double>::quiet_NaN();
        auto safe = ComputeCaptureCrop({8, 6}, {nan, nan, nan});
        Check(safe.X == 0 && safe.Y == 0 && safe.Width == 8 && safe.Height == 6, "nonfinite viewport uses full source");
        auto invalid = ComputeCaptureCrop({0, 6}, {});
        Check(invalid.Width == 0 && invalid.Height == 0, "invalid source produces no crop");

        auto source = Grid(8, 6, 8);
        MonitorCaptureResult output{};
        Check(CropScreenFrame(source, {2, .5, .5}, {4, 3}, output) == PingCaptureSuccess, "crop accepts padded source stride");
        Check(output.BgraPixels[0] == 2 && output.BgraPixels[1] == 2 && output.RowPitch == 16,
            "preview starts at selected source pixel without copying padding");
        auto last = output.BgraPixels.size() - 4;
        Check(output.BgraPixels[last] == 5 && output.BgraPixels[last + 1] == 4, "crop retains selected bottom-right source pixel");
        Check(CropScreenFrame(source, {2, 1, 1}, {2, 2}, output) == PingCaptureSuccess,
            "crop can resize the selected region");
        Check(output.BgraPixels[0] == 4 && output.BgraPixels[1] == 3 && output.BgraPixels[12] == 6
            && output.BgraPixels[13] == 4, "resampling uses the selected edge region");

        source.RowPitch = 4;
        Check(CropScreenFrame(source, {}, {4, 4}, output) == PingCaptureCaptureFailure, "short source stride is rejected");
        source = Grid(8, 6);
        source.BgraPixels.pop_back();
        Check(CropScreenFrame(source, {}, {4, 4}, output) == PingCaptureCaptureFailure, "truncated source buffer is rejected");
        source = Grid(8, 6);
        Check(CropScreenFrame(source, {}, {std::numeric_limits<int>::max(), 2}, output) == PingCaptureCaptureFailure,
            "oversized output is rejected before allocation");
    }

    void CompositionChecks()
    {
        auto screen = Grid(40, 24, 8);
        auto cameraPixels = Grid(12, 8, 4);
        CameraFrameResult camera{cameraPixels.SourceSize, cameraPixels.RowPitch, cameraPixels.BgraPixels};
        OutputLayout layout{20, 12, 6, 13, 5, 20.0 / 12};
        std::vector<std::uint8_t> output;
        Check(ComposeScreenFaceFrame(layout, screen, camera, {2, .5, .5}, output) == PingCaptureSuccess,
            "screen and circular camera compose from owned synthetic sources");
        Check(output[0] == 10 && output[1] == 6, "recorded frame uses the same viewport as preview");
        auto corner = (static_cast<size_t>(5) * 20 + 13) * 4;
        Check(output[corner] == 23 && output[corner + 1] == 11, "camera square corners leave the selected screen visible");
        auto center = (static_cast<size_t>(8) * 20 + 16) * 4;
        Check(output[center] == 6 && output[center + 1] == 4, "camera fills circle using central square crop");
        auto leftInner = (static_cast<size_t>(8) * 20 + 14) * 4;
        Check(output[leftInner] >= 2 && output[leftInner] <= 4, "wide camera is cropped rather than stretched");
        camera.BgraPixels.clear();
        Check(ComposeScreenFaceFrame(layout, screen, camera, {}, output) == PingCaptureNoCamera,
            "missing camera fails instead of fabricating a recorded face");
        camera = {cameraPixels.SourceSize, cameraPixels.RowPitch, cameraPixels.BgraPixels};
        layout.Width = 0;
        Check(ComposeScreenFaceFrame(layout, screen, camera, {}, output) == PingCaptureCaptureFailure,
            "invalid layout is rejected before composition");
    }

    void LayoutChecks()
    {
        auto odd = CreateScreenFaceLayout({1919, 1079}, .32);
        Check(odd.Width == 1918 && odd.Height == 1078, "odd source is aligned to even encoder dimensions");
        auto portrait = CreateScreenFaceLayout({1080, 3840}, .32);
        Check(portrait.Width == 540 && portrait.Height == 1920, "portrait output also respects1920 long-side cap");
        auto landscape = CreateScreenFaceLayout({3840, 2160}, .32);
        Check(landscape.Width == 1920 && landscape.Height == 1080, "landscape keeps display aspect and encoder cap");
        Check(landscape.FaceDiameter == 346 && landscape.FaceX == 1525 && landscape.FaceY == 685,
            "face diameter and padding preserve Mac ratios");
        auto tiny = CreateScreenFaceLayout({1, 1}, .32);
        Check(tiny.Width == 2 && tiny.Height == 2, "tiny source remains encodable without zero dimensions");
        auto invalid = CreateScreenFaceLayout({0, 1}, .32);
        Check(invalid.Width == 0 && invalid.Height == 0, "invalid layout dimensions cannot enter encoder");
        auto mac = CreateScreenFaceLayout({3840, 2160}, .32, 540);
        Check(mac.Width == 540 && mac.Height == 304, "screen message uses Mac540 long-side budget with even codec alignment");
    }

    void EntryPointChecks(wchar_t const* directory)
    {
        auto path = std::wstring(directory) + L"\\abi-fixture-unused.mp4";
        HANDLE cancellation = CreateEventW(nullptr, TRUE, TRUE, nullptr);
        Check(cancellation != nullptr, "fixture owns native cancellation event");
        double aspect = 0;
        int record = PingCapture_RecordScreenFaceMp4V2(path.c_str(), 3000, 0, .32, 2, .5, .5, cancellation, &aspect);
        int preview = PingCapture_WriteScreenPreviewBmpV2(path.c_str(), 0, 2, .5, .5, cancellation, &aspect);
        CloseHandle(cancellation);
        Check(record == PingCaptureCancelled && preview == PingCaptureCancelled, "versioned entries honor cancellation before source startup");
        Check(FixtureSourceStarts == 0, "pre-cancelled entries never start any capture source");
        Check(PingCapture_RecordScreenFaceMp4V2(path.c_str(), 0, 0, .32, 1, .5, .5, nullptr, &aspect) == PingCaptureEncoderFailure,
            "invalid duration is rejected before source startup");
        Check(PingCapture_WriteScreenPreviewBmp(nullptr, 0, &aspect) == PingCaptureCaptureFailure,
            "legacy preview keeps path validation contract");
        Check(GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES, "rejected entries create no output file");
    }
}

int wmain(int argc, wchar_t* argv[])
{
    try
    {
        if (argc != 2) throw std::runtime_error("Owned artifact directory is required.");
        CropChecks(); CompositionChecks(); LayoutChecks(); EntryPointChecks(argv[1]);
        EncoderChecks(argv[1], Check);
        RecordingStreamChecks(argv[1], Check);
        PixelViewChecks(Check);
        LiveRecordingChecks(Check);
        LiveEntryChecks(argv[1], Check);
        MicrophonePacketChecks(Check);
        ScreenSnapshotChecks(argv[1], Check);
        CameraSampleChecks(Check);
        std::cout << "PASS: " << checks << " native synthetic composition checks. No device capture.\n";
        return 0;
    }
    catch (std::exception const& error)
    {
        std::cerr << "FAIL after " << checks << " checks: " << error.what() << '\n';
        return 1;
    }
}
