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
    constexpr LONGLONG OneSecond = 10'000'000;

    struct MediaFoundationScope { ~MediaFoundationScope() { MFShutdown(); } };

    HRESULT SetMediaTypeUInt32(IMFMediaType* mediaType, REFGUID key, UINT32 value)
    {
        return mediaType->SetUINT32(key, value);
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
        int durationMs, CaptureViewport viewport, HANDLE cancellationEvent)
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

        if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;
        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return PingCaptureEncoderFailure;
        }
        MediaFoundationScope foundationScope;

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
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(videoOutputType.Get(), MF_MT_AVG_BITRATE, 1'200'000);
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
        // Owned BGRA frames are top-down; the default RGB interpretation can invert the encoded image.
        if (SUCCEEDED(hr)) hr = videoInputType->SetUINT32(MF_MT_DEFAULT_STRIDE, static_cast<UINT32>(layout.Width) * 4);
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
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(audioOutputType.Get(), MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 8'000);
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

        bool cancelled = false;
        for (int frameIndex = 0; SUCCEEDED(hr) && frameIndex < frameCount; ++frameIndex)
        {
            if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0)
            { cancelled = true; break; }
            LONGLONG sampleTime = static_cast<LONGLONG>(frameIndex) * frameDuration;
            auto screenIndex = std::min(
                screenFrames.size() - 1,
                static_cast<size_t>((static_cast<long long>(frameIndex) * screenFrames.size()) / frameCount));
            auto cameraIndex = std::min(
                cameraFrames.size() - 1,
                static_cast<size_t>((static_cast<long long>(frameIndex) * cameraFrames.size()) / frameCount));
            std::vector<std::uint8_t> videoFrame;
            if (ComposeScreenFaceFrame(layout, screenFrames[screenIndex], cameraFrames[cameraIndex], viewport, videoFrame) != PingCaptureSuccess)
            { hr = E_FAIL; break; }
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

        if (sinkWriter && !cancelled)
        {
            HRESULT finalizeResult = sinkWriter->Finalize();
            if (SUCCEEDED(hr))
            {
                hr = finalizeResult;
            }
        }
        return cancelled ? PingCaptureCancelled : SUCCEEDED(hr) ? PingCaptureSuccess : PingCaptureEncoderFailure;
    }
}
