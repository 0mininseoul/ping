#include "PingCaptureEngine.h"
#include "RecordingStream.h"

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

    struct MediaFoundationScope { bool Started = false; ~MediaFoundationScope() { if (Started) MFShutdown(); } };
    struct ApartmentScope { bool Initialized = false; ~ApartmentScope() { if (Initialized) CoUninitialize(); } };

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
    namespace
    {
        struct ProviderScope
        {
            IRecordingFrameProvider& Provider;
            ~ProviderScope() { Provider.Stop(); }
        };
        struct OutputScope
        {
            wchar_t const* Path;
            bool Touched = false, Keep = false;
            ~OutputScope() { if (Touched && !Keep) DeleteFileW(Path); }
        };
        class VectorProvider final : public IRecordingFrameProvider
        {
        public:
            VectorProvider(std::vector<MonitorCaptureResult> const& screens, std::vector<CameraFrameResult> const& cameras,
                AudioCaptureResult const& audio, int durationMs) : screens_(screens), cameras_(cameras), audio_(audio),
                count_(std::max(1, (durationMs * FramesPerSecond + 999) / 1000)) {}
            int ReadFrame(LONGLONG time, LONGLONG duration, RecordingFramePacket& packet, HANDLE) override
            {
                if (screens_.empty() || cameras_.empty() || audio_.SamplesPerSecond != 48'000 || audio_.Channels != 1
                    || audio_.BitsPerSample != 16) return PingCaptureCaptureFailure;
                auto screen = std::min(screens_.size() - 1, index_ * screens_.size() / count_);
                auto camera = std::min(cameras_.size() - 1, index_ * cameras_.size() / count_);
                ++index_;
                auto first = static_cast<size_t>(time * 48'000 / OneSecond) * 2;
                auto end = static_cast<size_t>((time + duration) * 48'000 / OneSecond) * 2;
                if (end > audio_.PcmBytes.size() || first >= end) return PingCaptureNoMicrophone;
                packet.Screen = std::shared_ptr<MonitorCaptureResult const>(&screens_[screen], [](auto*) {});
                packet.Camera = std::shared_ptr<CameraFrameResult const>(&cameras_[camera], [](auto*) {});
                packet.Audio.assign(audio_.PcmBytes.begin() + static_cast<std::ptrdiff_t>(first),
                    audio_.PcmBytes.begin() + static_cast<std::ptrdiff_t>(end));
                return PingCaptureSuccess;
            }
            void Stop() noexcept override {}
        private:
            std::vector<MonitorCaptureResult> const& screens_;
            std::vector<CameraFrameResult> const& cameras_;
            AudioCaptureResult const& audio_;
            size_t index_ = 0;
            int count_;
        };
    }

    static int WriteStreamCore(
        const wchar_t* outputPath,
        OutputLayout const& layout,
        IRecordingFrameProvider& provider,
        int durationMs, CaptureViewport viewport, HANDLE cancellationEvent, bool& outputTouched,
        ApartmentScope& apartment, MediaFoundationScope& foundation, PingCapturePreviewCallback preview, void* previewContext)
    {
        if (outputPath == nullptr
            || outputPath[0] == L'\0'
            || layout.Width < 2 || layout.Width > 1920 || layout.Width % 2 != 0
            || layout.Height < 2 || layout.Height > 1920 || layout.Height % 2 != 0
            || durationMs <= 0 || durationMs > 30'000)
        {
            return PingCaptureEncoderFailure;
        }

        if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;
        auto apartmentResult = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        if (FAILED(apartmentResult) && apartmentResult != RPC_E_CHANGED_MODE) return PingCaptureEncoderFailure;
        apartment.Initialized = SUCCEEDED(apartmentResult);
        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return PingCaptureEncoderFailure;
        }
        foundation.Started = true;
        const AudioCaptureResult audio{48'000, 1, 16, {}};

        ComPtr<IMFAttributes> writerAttributes;
        hr = MFCreateAttributes(&writerAttributes, 1);
        if (SUCCEEDED(hr))
        {
            hr = writerAttributes->SetUINT32(MF_SINK_WRITER_DISABLE_THROTTLING, FALSE);
        }

        ComPtr<IMFSinkWriter> sinkWriter;
        if (SUCCEEDED(hr))
        {
            outputTouched = true;
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
        const auto totalDuration = static_cast<LONGLONG>(durationMs) * 10'000;
        int sourceResult = PingCaptureSuccess;
        for (int frameIndex = 0; SUCCEEDED(hr) && frameIndex < frameCount; ++frameIndex)
        {
            if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0)
            { sourceResult = PingCaptureCancelled; break; }
            LONGLONG sampleTime = static_cast<LONGLONG>(frameIndex) * OneSecond / FramesPerSecond;
            auto frameEnd = std::min(totalDuration, static_cast<LONGLONG>(frameIndex + 1) * OneSecond / FramesPerSecond);
            auto frameDuration = frameEnd - sampleTime;
            RecordingFramePacket packet;
            sourceResult = provider.ReadFrame(sampleTime, frameDuration, packet, cancellationEvent);
            if (sourceResult != PingCaptureSuccess) break;
            if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0)
            { sourceResult = PingCaptureCancelled; break; }
            auto requiredAudio = static_cast<size_t>((frameEnd * 48'000 / OneSecond) - (sampleTime * 48'000 / OneSecond)) * 2;
            if (!packet.Screen || !packet.Camera || packet.Audio.size() != requiredAudio)
            { sourceResult = PingCaptureCaptureFailure; break; }
            std::vector<std::uint8_t> videoFrame;
            if (ComposeScreenFaceFrame(layout, *packet.Screen, *packet.Camera, viewport, videoFrame) != PingCaptureSuccess)
            { hr = E_FAIL; break; }
            hr = WriteSample(sinkWriter.Get(), videoStreamIndex, videoFrame, sampleTime, frameDuration);
            if (SUCCEEDED(hr) && preview) preview(videoFrame.data(), layout.Width, layout.Height, layout.Width * 4, previewContext);
            if (SUCCEEDED(hr))
            {
                hr = WriteSample(sinkWriter.Get(), audioStreamIndex, packet.Audio, sampleTime, frameDuration);
            }
        }

        if (sinkWriter && SUCCEEDED(hr) && sourceResult == PingCaptureSuccess)
        {
            HRESULT finalizeResult = sinkWriter->Finalize();
            if (SUCCEEDED(hr))
            {
                hr = finalizeResult;
            }
        }
        if (cancellationEvent && WaitForSingleObject(cancellationEvent, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;
        return sourceResult != PingCaptureSuccess ? sourceResult : SUCCEEDED(hr) ? PingCaptureSuccess : PingCaptureEncoderFailure;
    }

    int WriteScreenFaceMp4Stream(const wchar_t* outputPath, OutputLayout const& layout,
        IRecordingFrameProvider& provider, int durationMs, CaptureViewport viewport, HANDLE cancellationEvent,
        PingCapturePreviewCallback preview, void* previewContext)
    {
        OutputScope output{outputPath};
        ApartmentScope apartment;
        MediaFoundationScope foundation;
        // Source Stop may release COM objects and wait for Media Foundation callbacks.
        ProviderScope source{provider};
        try
        {
            auto result = WriteStreamCore(outputPath, layout, provider, durationMs, viewport, cancellationEvent, output.Touched,
                apartment, foundation, preview, previewContext);
            output.Keep = result == PingCaptureSuccess;
            return result;
        }
        catch (...) { return PingCaptureCaptureFailure; }
    }

    int WriteScreenFaceMp4(const wchar_t* outputPath, OutputLayout const& layout,
        std::vector<MonitorCaptureResult> const& screenFrames, std::vector<CameraFrameResult> const& cameraFrames,
        AudioCaptureResult const& audio, int durationMs, CaptureViewport viewport, HANDLE cancellationEvent)
    {
        if (durationMs <= 0 || durationMs > 30'000) return PingCaptureEncoderFailure;
        VectorProvider provider{screenFrames, cameraFrames, audio, durationMs};
        return WriteScreenFaceMp4Stream(outputPath, layout, provider, durationMs, viewport, cancellationEvent);
    }
}
