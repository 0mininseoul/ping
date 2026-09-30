#include "PingCaptureEngine.h"
#include <array>
#include <cmath>
#include <cstring>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <stdexcept>
#include <iostream>
#include <string>

using namespace Ping::Windows::NativeCapture;
using Microsoft::WRL::ComPtr;

namespace
{
    struct ComScope { ~ComScope() { CoUninitialize(); } };
    struct MfScope { ~MfScope() { MFShutdown(); } };
    using Color = std::array<int, 3>;
    constexpr DWORD VideoStream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_VIDEO_STREAM);
    constexpr DWORD AudioStream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
    constexpr DWORD MediaSource = static_cast<DWORD>(MF_SOURCE_READER_MEDIASOURCE);

    bool Near(Color actual, Color expected)
    {
        return std::abs(actual[0] - expected[0]) < 25 && std::abs(actual[1] - expected[1]) < 25
            && std::abs(actual[2] - expected[2]) < 25;
    }

    std::array<Color, 3> DecodeColors(IMFSourceReader* reader, void (*check)(bool, char const*))
    {
        ComPtr<IMFMediaType> requested;
        check(SUCCEEDED(MFCreateMediaType(&requested)), "decoded fixture media type created");
        requested->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        requested->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
        check(SUCCEEDED(reader->SetCurrentMediaType(VideoStream, nullptr, requested.Get())),
            "actual encoded fixture decodes to RGB32");
        ComPtr<IMFSample> sample;
        DWORD flags = 0, stream = 0;
        LONGLONG timestamp = 0;
        for (int attempt = 0; attempt < 10 && !sample; ++attempt)
            check(SUCCEEDED(reader->ReadSample(VideoStream, 0, &stream, &flags, &timestamp, &sample)),
                "actual encoded frame can be read");
        check(sample != nullptr, "actual decoder returned video pixels");
        ComPtr<IMFMediaBuffer> buffer;
        check(SUCCEEDED(sample->ConvertToContiguousBuffer(&buffer)), "decoded frame buffer is available");
        ComPtr<IMF2DBuffer> twoD;
        BYTE* scanline = nullptr;
        LONG pitch = 0;
        bool locked2D = SUCCEEDED(buffer.As(&twoD));
        if (locked2D)
            check(SUCCEEDED(twoD->Lock2D(&scanline, &pitch)), "decoded scanline and signed stride are available");
        else
        {
            ComPtr<IMFMediaType> current;
            reader->GetCurrentMediaType(VideoStream, &current);
            UINT32 rawStride = 0;
            if (SUCCEEDED(current->GetUINT32(MF_MT_DEFAULT_STRIDE, &rawStride))) pitch = static_cast<LONG>(rawStride);
            else MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, 540, &pitch);
            DWORD length = 0;
            check(SUCCEEDED(buffer->Lock(&scanline, nullptr, &length)) && length >= static_cast<UINT32>(std::abs(pitch)) * 304,
                "decoded contiguous buffer has validated extent");
            if (pitch < 0) scanline += static_cast<size_t>(-pitch) * 303;
        }
        std::array<Color, 3> colors{};
        const std::array<std::pair<int, int>, 3> points = {{{20, 20}, {20, 280}, {477, 241}}};
        for (size_t i = 0; i < points.size(); ++i)
        {
            auto pixel = scanline + static_cast<ptrdiff_t>(points[i].second) * pitch + points[i].first * 4;
            colors[i] = {pixel[0], pixel[1], pixel[2]};
        }
        if (locked2D) twoD->Unlock2D(); else buffer->Unlock();
        std::cout << "Decoded stride=" << pitch << ", colors=";
        for (auto const& color : colors) std::cout << '[' << color[0] << ',' << color[1] << ',' << color[2] << ']';
        std::cout << '\n';
        return colors;
    }
}

void VerifyStreamingClip(wchar_t const* path, void (*check)(bool, char const*))
{
    check(SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)), "stream verifier owns COM apartment");
    ComScope com;
    check(SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE)), "stream verifier owns Media Foundation lifetime");
    MfScope mf;
    ComPtr<IMFAttributes> attributes;
    MFCreateAttributes(&attributes, 1);
    attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
    ComPtr<IMFSourceReader> reader;
    check(SUCCEEDED(MFCreateSourceReaderFromURL(path, attributes.Get(), &reader)), "incremental MP4 opens for timeline verification");
    ComPtr<IMFMediaType> type;
    MFCreateMediaType(&type); type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video); type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    check(SUCCEEDED(reader->SetCurrentMediaType(VideoStream, nullptr, type.Get())), "timeline video decodes to RGB32");
    bool earlyVideo = false, lateVideo = false;
    for (int attempt = 0; attempt < 100; ++attempt)
    {
        ComPtr<IMFSample> sample;
        DWORD flags = 0, stream = 0; LONGLONG time = 0;
        auto hr = reader->ReadSample(VideoStream, 0, &stream, &flags, &time, &sample);
        if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) break;
        if (!sample || (time < 2'000'000) || (earlyVideo && time < 25'000'000)) continue;
        ComPtr<IMFMediaBuffer> buffer; sample->ConvertToContiguousBuffer(&buffer);
        BYTE* data = nullptr; DWORD length = 0;
        if (!buffer || FAILED(buffer->Lock(&data, nullptr, &length))) break;
        int actual = length >= 4 ? data[0] : -1;
        buffer->Unlock();
        if (!earlyVideo) earlyVideo = actual >= 0 && actual <= 15;
        else { lateVideo = actual >= 70 && actual <= 89; break; }
    }
    check(earlyVideo && lateVideo, "encoded early and late frames preserve changing source time");

    reader.Reset();
    check(SUCCEEDED(MFCreateSourceReaderFromURL(path, nullptr, &reader)), "stream audio opens independently");
    type.Reset(); MFCreateMediaType(&type);
    type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio); type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 48'000); type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1);
    type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    check(SUCCEEDED(reader->SetCurrentMediaType(AudioStream, nullptr, type.Get())), "stream AAC decodes to mono PCM");
    double earlySquares = 0, lateSquares = 0;
    size_t earlyCount = 0, lateCount = 0;
    LONGLONG previous = -1;
    bool monotonic = true;
    for (int attempt = 0; attempt < 200; ++attempt)
    {
        ComPtr<IMFSample> sample;
        DWORD flags = 0, stream = 0; LONGLONG time = 0;
        auto hr = reader->ReadSample(AudioStream, 0, &stream, &flags, &time, &sample);
        if (FAILED(hr)) { monotonic = false; break; }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
        if (!sample) continue;
        if (time < previous) monotonic = false;
        previous = time;
        if ((time < 2'000'000 || time > 8'000'000) && (time < 22'000'000 || time > 28'000'000)) continue;
        ComPtr<IMFMediaBuffer> buffer; sample->ConvertToContiguousBuffer(&buffer);
        BYTE* data = nullptr; DWORD length = 0;
        if (!buffer || FAILED(buffer->Lock(&data, nullptr, &length))) { monotonic = false; break; }
        for (DWORD i = 0; i + 1 < length; i += 2)
        {
            std::int16_t value = 0; std::memcpy(&value, data + i, 2);
            if (time < 10'000'000) { earlySquares += static_cast<double>(value) * value; ++earlyCount; }
            else { lateSquares += static_cast<double>(value) * value; ++lateCount; }
        }
        buffer->Unlock();
    }
    check(monotonic && earlyCount > 10'000 && lateCount > 10'000 && previous >= 29'000'000,
        "decoded audio clock is monotonic and reaches final video second");
    auto earlyRms = earlyCount ? std::sqrt(earlySquares / earlyCount) : 0;
    auto lateRms = lateCount ? std::sqrt(lateSquares / lateCount) : 0;
    std::cout << "Decoded PCM RMS early=" << earlyRms << ", late=" << lateRms << '\n';
    check(earlyRms > 900 && earlyRms < 2000 && lateRms > 5'000 && lateRms > earlyRms * 3,
        "encoded early and late audio preserve source timing and amplitude");
}

void EncoderChecks(wchar_t const* directory, void (*check)(bool, char const*))
{
    check(SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)), "fixture initializes owned COM apartment");
    ComScope com;
    check(SUCCEEDED(MFStartup(MF_VERSION, MFSTARTUP_LITE)), "fixture initializes Media Foundation without device sources");
    MfScope mf;
    MonitorCaptureResult screen{};
    screen.SourceSize = {960, 540};
    screen.RowPitch = 960 * 4;
    screen.BgraPixels.resize(960 * 540 * 4);
    for (int y = 0; y < 540; ++y)
        for (int x = 0; x < 960; ++x)
        {
            Color color = y < 270 ? (x < 480 ? Color{0, 0, 255} : Color{0, 255, 0})
                : (x < 480 ? Color{255, 0, 0} : Color{0, 255, 255});
            auto pixel = screen.BgraPixels.data() + (static_cast<size_t>(y) * 960 + x) * 4;
            for (int channel = 0; channel < 3; ++channel) pixel[channel] = static_cast<std::uint8_t>(color[channel]);
            pixel[3] = 255;
        }
    CameraFrameResult camera{};
    camera.SourceSize = {192, 108}; camera.RowPitch = 192 * 4;
    camera.BgraPixels.resize(192 * 108 * 4);
    for (size_t i = 0; i < camera.BgraPixels.size(); i += 4)
    { camera.BgraPixels[i] = 180; camera.BgraPixels[i + 1] = 20; camera.BgraPixels[i + 2] = 160; camera.BgraPixels[i + 3] = 255; }
    AudioCaptureResult audio{48'000, 1, 16, {}};
    audio.PcmBytes.resize(48'000 * 3 * 2);
    for (int i = 0; i < 48'000 * 3; ++i)
    {
        auto value = static_cast<std::int16_t>(3000 * std::sin(i * 440 * 2 * 3.141592653589793 / 48'000));
        std::memcpy(audio.PcmBytes.data() + i * 2, &value, 2);
    }
    auto path = std::wstring(directory) + L"\\synthetic-screen-face.mp4";
    auto layout = CreateScreenFaceLayout(screen.SourceSize, .32, 540);
    check(WriteScreenFaceMp4(path.c_str(), layout, {screen}, {camera}, audio, 3000, {2, .5, .5}) == PingCaptureSuccess,
        "actual sink writer encodes synthetic3second viewport clip");
    ComPtr<IMFAttributes> attributes;
    MFCreateAttributes(&attributes, 1);
    attributes->SetUINT32(MF_SOURCE_READER_ENABLE_VIDEO_PROCESSING, TRUE);
    ComPtr<IMFSourceReader> reader;
    check(SUCCEEDED(MFCreateSourceReaderFromURL(path.c_str(), attributes.Get(), &reader)), "actual encoded MP4 opens for verification");
    ComPtr<IMFMediaType> video, sound;
    GUID subtype{};
    reader->GetNativeMediaType(VideoStream, 0, &video);
    check(video && SUCCEEDED(video->GetGUID(MF_MT_SUBTYPE, &subtype)) && subtype == MFVideoFormat_H264,
        "encoded video uses H264");
    UINT32 width = 0, height = 0;
    MFGetAttributeSize(video.Get(), MF_MT_FRAME_SIZE, &width, &height);
    check(width == 540 && height == 304, "encoded frame dimensions match Mac message budget");
    reader->GetNativeMediaType(AudioStream, 0, &sound);
    check(sound && SUCCEEDED(sound->GetGUID(MF_MT_SUBTYPE, &subtype)) && subtype == MFAudioFormat_AAC,
        "encoded clip contains AAC microphone-format track");
    UINT32 audioBytesPerSecond = 0;
    check(SUCCEEDED(sound->GetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, &audioBytesPerSecond)) && audioBytesPerSecond == 8'000,
        "encoded AAC stream preserves64kbps budget");
    PROPVARIANT duration{};
    auto hr = reader->GetPresentationAttribute(MediaSource, MF_PD_DURATION, &duration);
    bool threeSeconds = SUCCEEDED(hr) && duration.vt == VT_UI8 && duration.uhVal.QuadPart >= 29'500'000
        && duration.uhVal.QuadPart <= 31'000'000;
    PropVariantClear(&duration);
    check(threeSeconds, "actual clip duration remains three seconds");
    auto colors = DecodeColors(reader.Get(), check);
    check(Near(colors[0], {0, 0, 255}), "decoded viewport preserves top-left red quadrant");
    check(Near(colors[1], {255, 0, 0}), "decoded viewport preserves bottom-left blue quadrant without inversion");
    check(Near(colors[2], {180, 20, 160}), "decoded face remains in bottom-right circle");
}
