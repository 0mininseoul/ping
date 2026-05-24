#include "PingCaptureEngine.h"

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <vector>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace
{
    constexpr int FramesPerSecond = 30;
    constexpr int AudioSamplesPerSecond = 48'000;
    constexpr int AudioChannels = 1;
    constexpr int AudioBitsPerSample = 16;
    constexpr LONGLONG OneSecond = 10'000'000;

    HRESULT SetMediaTypeUInt32(IMFMediaType* mediaType, REFGUID key, UINT32 value)
    {
        return mediaType->SetUINT32(key, value);
    }

    std::uint8_t const* PixelAt(
        std::vector<std::uint8_t> const& pixels,
        std::uint32_t rowPitch,
        int x,
        int y)
    {
        return pixels.data() + static_cast<size_t>(y) * rowPitch + static_cast<size_t>(x) * 4;
    }

    void CopyPixel(std::uint8_t* destination, std::uint8_t const* source)
    {
        destination[0] = source[0];
        destination[1] = source[1];
        destination[2] = source[2];
        destination[3] = 0xff;
    }

    void FillPixel(std::uint8_t* destination, std::uint8_t b, std::uint8_t g, std::uint8_t r)
    {
        destination[0] = b;
        destination[1] = g;
        destination[2] = r;
        destination[3] = 0xff;
    }

    std::vector<std::uint8_t> ComposeFrame(
        Ping::Windows::NativeCapture::OutputLayout const& layout,
        Ping::Windows::NativeCapture::MonitorCaptureResult const& screenFrame,
        Ping::Windows::NativeCapture::CameraFrameResult const& cameraFrame)
    {
        std::vector<std::uint8_t> frame(static_cast<size_t>(layout.Width) * static_cast<size_t>(layout.Height) * 4);

        for (int y = 0; y < layout.Height; ++y)
        {
            int sourceY = std::clamp(
                static_cast<int>((static_cast<long long>(y) * screenFrame.SourceSize.Height) / layout.Height),
                0,
                std::max(0, screenFrame.SourceSize.Height - 1));
            for (int x = 0; x < layout.Width; ++x)
            {
                int sourceX = std::clamp(
                    static_cast<int>((static_cast<long long>(x) * screenFrame.SourceSize.Width) / layout.Width),
                    0,
                    std::max(0, screenFrame.SourceSize.Width - 1));
                auto* destination = frame.data() + (static_cast<size_t>(y) * layout.Width + x) * 4;
                if (!screenFrame.BgraPixels.empty())
                {
                    CopyPixel(destination, PixelAt(screenFrame.BgraPixels, screenFrame.RowPitch, sourceX, sourceY));
                }
                else
                {
                    FillPixel(destination, 0x1f, 0x21, 0x25);
                }
            }
        }

        int radius = layout.FaceDiameter / 2;
        int centerX = layout.FaceX + radius;
        int centerY = layout.FaceY + radius;
        int innerRadiusSquared = std::max(0, radius - 2) * std::max(0, radius - 2);
        int outerRadiusSquared = radius * radius;

        for (int y = 0; y < layout.FaceDiameter; ++y)
        {
            int destinationY = layout.FaceY + y;
            if (destinationY < 0 || destinationY >= layout.Height)
            {
                continue;
            }

            for (int x = 0; x < layout.FaceDiameter; ++x)
            {
                int destinationX = layout.FaceX + x;
                if (destinationX < 0 || destinationX >= layout.Width)
                {
                    continue;
                }

                int dx = destinationX - centerX;
                int dy = destinationY - centerY;
                int distanceSquared = dx * dx + dy * dy;
                if (distanceSquared > outerRadiusSquared)
                {
                    continue;
                }

                auto* destination = frame.data() + (static_cast<size_t>(destinationY) * layout.Width + destinationX) * 4;
                if (distanceSquared > innerRadiusSquared)
                {
                    FillPixel(destination, 0xff, 0xff, 0xff);
                    continue;
                }

                if (!cameraFrame.BgraPixels.empty())
                {
                    int cameraX = std::clamp(
                        static_cast<int>((static_cast<long long>(x) * cameraFrame.SourceSize.Width) / layout.FaceDiameter),
                        0,
                        std::max(0, cameraFrame.SourceSize.Width - 1));
                    int cameraY = std::clamp(
                        static_cast<int>((static_cast<long long>(y) * cameraFrame.SourceSize.Height) / layout.FaceDiameter),
                        0,
                        std::max(0, cameraFrame.SourceSize.Height - 1));
                    CopyPixel(destination, PixelAt(cameraFrame.BgraPixels, cameraFrame.RowPitch, cameraX, cameraY));
                }
                else
                {
                    FillPixel(destination, 0x30, 0x30, 0x30);
                }
            }
        }

        return frame;
    }

    HRESULT WriteSample(
        IMFSinkWriter* sinkWriter,
        DWORD streamIndex,
        std::vector<std::uint8_t> const& bytes,
        LONGLONG sampleTime,
        LONGLONG sampleDuration)
    {
        ComPtr<IMFMediaBuffer> buffer;
        HRESULT hr = MFCreateMemoryBuffer(static_cast<DWORD>(bytes.size()), &buffer);
        if (FAILED(hr))
        {
            return hr;
        }

        BYTE* destination = nullptr;
        DWORD maxLength = 0;
        DWORD currentLength = 0;
        hr = buffer->Lock(&destination, &maxLength, &currentLength);
        if (FAILED(hr))
        {
            return hr;
        }

        std::memcpy(destination, bytes.data(), bytes.size());
        buffer->Unlock();
        if (SUCCEEDED(hr)) hr = buffer->SetCurrentLength(static_cast<DWORD>(bytes.size()));

        ComPtr<IMFSample> sample;
        if (SUCCEEDED(hr)) hr = MFCreateSample(&sample);
        if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer.Get());
        if (SUCCEEDED(hr)) hr = sample->SetSampleTime(sampleTime);
        if (SUCCEEDED(hr)) hr = sample->SetSampleDuration(sampleDuration);
        if (SUCCEEDED(hr)) hr = sinkWriter->WriteSample(streamIndex, sample.Get());
        return hr;
    }
}

namespace Ping::Windows::NativeCapture
{
    int WriteScreenFaceMp4(
        const wchar_t* outputPath,
        OutputLayout const& layout,
        std::vector<MonitorCaptureResult> const& screenFrames,
        std::vector<CameraFrameResult> const& cameraFrames,
        AudioCaptureResult const& audio,
        int durationMs)
    {
        if (outputPath == nullptr
            || outputPath[0] == L'\0'
            || layout.Width <= 0
            || layout.Height <= 0
            || durationMs <= 0
            || screenFrames.empty()
            || cameraFrames.empty()
            || audio.PcmBytes.empty())
        {
            return PingCaptureEncoderFailure;
        }

        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return PingCaptureEncoderFailure;
        }

        ComPtr<IMFAttributes> writerAttributes;
        hr = MFCreateAttributes(&writerAttributes, 1);
        if (SUCCEEDED(hr))
        {
            writerAttributes->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, TRUE);
        }

        ComPtr<IMFSinkWriter> sinkWriter;
        if (SUCCEEDED(hr))
        {
            hr = MFCreateSinkWriterFromURL(outputPath, nullptr, writerAttributes.Get(), &sinkWriter);
        }

        DWORD videoStreamIndex = 0;
        ComPtr<IMFMediaType> videoOutputType;
        if (SUCCEEDED(hr)) hr = MFCreateMediaType(&videoOutputType);
        if (SUCCEEDED(hr)) hr = videoOutputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = videoOutputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(videoOutputType.Get(), MF_MT_AVG_BITRATE, 8'000'000);
        if (SUCCEEDED(hr)) hr = MFSetAttributeSize(videoOutputType.Get(), MF_MT_FRAME_SIZE, layout.Width, layout.Height);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(videoOutputType.Get(), MF_MT_FRAME_RATE, FramesPerSecond, 1);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(videoOutputType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        if (SUCCEEDED(hr)) hr = videoOutputType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        if (SUCCEEDED(hr)) hr = sinkWriter->AddStream(videoOutputType.Get(), &videoStreamIndex);

        ComPtr<IMFMediaType> videoInputType;
        if (SUCCEEDED(hr)) hr = MFCreateMediaType(&videoInputType);
        if (SUCCEEDED(hr)) hr = videoInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = videoInputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_ARGB32);
        if (SUCCEEDED(hr)) hr = MFSetAttributeSize(videoInputType.Get(), MF_MT_FRAME_SIZE, layout.Width, layout.Height);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(videoInputType.Get(), MF_MT_FRAME_RATE, FramesPerSecond, 1);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(videoInputType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        if (SUCCEEDED(hr)) hr = videoInputType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        if (SUCCEEDED(hr)) hr = sinkWriter->SetInputMediaType(videoStreamIndex, videoInputType.Get(), nullptr);

        DWORD audioStreamIndex = 0;
        ComPtr<IMFMediaType> audioOutputType;
        if (SUCCEEDED(hr)) hr = MFCreateMediaType(&audioOutputType);
        if (SUCCEEDED(hr)) hr = audioOutputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        if (SUCCEEDED(hr)) hr = audioOutputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioOutputType.Get(), MF_MT_AUDIO_NUM_CHANNELS, audio.Channels);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioOutputType.Get(), MF_MT_AUDIO_SAMPLES_PER_SECOND, audio.SamplesPerSecond);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioOutputType.Get(), MF_MT_AUDIO_BITS_PER_SAMPLE, audio.BitsPerSample);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioOutputType.Get(), MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 12'000);
        if (SUCCEEDED(hr)) hr = sinkWriter->AddStream(audioOutputType.Get(), &audioStreamIndex);

        ComPtr<IMFMediaType> audioInputType;
        if (SUCCEEDED(hr)) hr = MFCreateMediaType(&audioInputType);
        if (SUCCEEDED(hr)) hr = audioInputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        if (SUCCEEDED(hr)) hr = audioInputType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioInputType.Get(), MF_MT_AUDIO_NUM_CHANNELS, audio.Channels);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioInputType.Get(), MF_MT_AUDIO_SAMPLES_PER_SECOND, audio.SamplesPerSecond);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioInputType.Get(), MF_MT_AUDIO_BITS_PER_SAMPLE, audio.BitsPerSample);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioInputType.Get(), MF_MT_AUDIO_BLOCK_ALIGNMENT, audio.Channels * audio.BitsPerSample / 8);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioInputType.Get(), MF_MT_AUDIO_AVG_BYTES_PER_SECOND, audio.SamplesPerSecond * audio.Channels * audio.BitsPerSample / 8);
        if (SUCCEEDED(hr)) hr = sinkWriter->SetInputMediaType(audioStreamIndex, audioInputType.Get(), nullptr);
        if (SUCCEEDED(hr)) hr = sinkWriter->BeginWriting();

        auto frameCount = std::max(1, static_cast<int>((static_cast<long long>(durationMs) * FramesPerSecond + 999) / 1000));
        auto frameDuration = OneSecond / FramesPerSecond;
        auto bytesPerSecond = static_cast<size_t>(audio.SamplesPerSecond) * audio.Channels * audio.BitsPerSample / 8;

        for (int frameIndex = 0; SUCCEEDED(hr) && frameIndex < frameCount; ++frameIndex)
        {
            LONGLONG sampleTime = static_cast<LONGLONG>(frameIndex) * frameDuration;
            auto screenIndex = std::min(
                screenFrames.size() - 1,
                static_cast<size_t>((static_cast<long long>(frameIndex) * screenFrames.size()) / frameCount));
            auto cameraIndex = std::min(
                cameraFrames.size() - 1,
                static_cast<size_t>((static_cast<long long>(frameIndex) * cameraFrames.size()) / frameCount));
            auto videoFrame = ComposeFrame(layout, screenFrames[screenIndex], cameraFrames[cameraIndex]);
            hr = WriteSample(sinkWriter.Get(), videoStreamIndex, videoFrame, sampleTime, frameDuration);
            if (SUCCEEDED(hr))
            {
                auto audioOffset = std::min(
                    audio.PcmBytes.size(),
                    static_cast<size_t>((static_cast<long long>(frameIndex) * bytesPerSecond) / FramesPerSecond));
                auto audioLength = std::min(
                    audio.PcmBytes.size() - audioOffset,
                    bytesPerSecond / FramesPerSecond);
                std::vector<std::uint8_t> audioBytes(
                    audio.PcmBytes.begin() + static_cast<std::ptrdiff_t>(audioOffset),
                    audio.PcmBytes.begin() + static_cast<std::ptrdiff_t>(audioOffset + audioLength));
                if (audioBytes.empty())
                {
                    audioBytes.resize(bytesPerSecond / FramesPerSecond);
                }

                hr = WriteSample(sinkWriter.Get(), audioStreamIndex, audioBytes, sampleTime, frameDuration);
            }
        }

        if (sinkWriter)
        {
            HRESULT finalizeResult = sinkWriter->Finalize();
            if (SUCCEEDED(hr))
            {
                hr = finalizeResult;
            }
        }
        MFShutdown();

        return SUCCEEDED(hr) ? PingCaptureSuccess : PingCaptureEncoderFailure;
    }
}
