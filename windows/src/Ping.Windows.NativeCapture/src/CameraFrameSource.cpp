#include "PingCaptureEngine.h"

#include <algorithm>
#include <chrono>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <utility>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace
{
    void ReleaseDevices(IMFActivate** devices, UINT32 deviceCount)
    {
        if (devices == nullptr)
        {
            return;
        }

        for (UINT32 index = 0; index < deviceCount; ++index)
        {
            if (devices[index] != nullptr)
            {
                devices[index]->Release();
            }
        }
        CoTaskMemFree(devices);
    }

    HRESULT EnumerateVideoDevices(IMFActivate*** devices, UINT32* deviceCount)
    {
        *devices = nullptr;
        *deviceCount = 0;

        ComPtr<IMFAttributes> attributes;
        HRESULT hr = MFCreateAttributes(&attributes, 1);
        if (SUCCEEDED(hr))
        {
            hr = attributes->SetGUID(
                MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
        }

        if (SUCCEEDED(hr))
        {
            hr = MFEnumDeviceSources(attributes.Get(), devices, deviceCount);
        }

        return hr;
    }

    HRESULT EnumerateAudioDevices(IMFActivate*** devices, UINT32* deviceCount)
    {
        *devices = nullptr;
        *deviceCount = 0;

        ComPtr<IMFAttributes> attributes;
        HRESULT hr = MFCreateAttributes(&attributes, 1);
        if (SUCCEEDED(hr))
        {
            hr = attributes->SetGUID(
                MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_AUDCAP_GUID);
        }

        if (SUCCEEDED(hr))
        {
            hr = MFEnumDeviceSources(attributes.Get(), devices, deviceCount);
        }

        return hr;
    }
}

namespace Ping::Windows::NativeCapture
{
    int ProbeCameraFrameSource()
    {
        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        IMFActivate** devices = nullptr;
        UINT32 deviceCount = 0;
        hr = EnumerateVideoDevices(&devices, &deviceCount);

        if (FAILED(hr))
        {
            MFShutdown();
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        ReleaseDevices(devices, deviceCount);
        MFShutdown();

        return deviceCount > 0 ? PingCaptureSuccess : PingCaptureNoCamera;
    }

    int CaptureCameraFrame(CameraFrameResult& result)
    {
        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        IMFActivate** devices = nullptr;
        UINT32 deviceCount = 0;
        hr = EnumerateVideoDevices(&devices, &deviceCount);
        if (FAILED(hr) || deviceCount == 0)
        {
            ReleaseDevices(devices, deviceCount);
            MFShutdown();
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        ComPtr<IMFMediaSource> mediaSource;
        hr = devices[0]->ActivateObject(IID_PPV_ARGS(&mediaSource));
        ReleaseDevices(devices, deviceCount);
        if (FAILED(hr))
        {
            MFShutdown();
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        ComPtr<IMFSourceReader> reader;
        hr = MFCreateSourceReaderFromMediaSource(mediaSource.Get(), nullptr, &reader);
        if (FAILED(hr))
        {
            mediaSource->Shutdown();
            MFShutdown();
            return PingCaptureNoCamera;
        }

        ComPtr<IMFMediaType> desiredType;
        hr = MFCreateMediaType(&desiredType);
        if (SUCCEEDED(hr)) hr = desiredType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = desiredType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
        if (SUCCEEDED(hr))
        {
            hr = reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, desiredType.Get());
        }
        if (FAILED(hr))
        {
            mediaSource->Shutdown();
            MFShutdown();
            return PingCaptureNoCamera;
        }

        ComPtr<IMFMediaType> currentType;
        hr = reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &currentType);
        UINT32 width = 0;
        UINT32 height = 0;
        if (SUCCEEDED(hr))
        {
            hr = MFGetAttributeSize(currentType.Get(), MF_MT_FRAME_SIZE, &width, &height);
        }

        if (FAILED(hr) || width == 0 || height == 0)
        {
            mediaSource->Shutdown();
            MFShutdown();
            return PingCaptureNoCamera;
        }

        for (int attempt = 0; attempt < 30; ++attempt)
        {
            DWORD streamIndex = 0;
            DWORD flags = 0;
            LONGLONG timestamp = 0;
            ComPtr<IMFSample> sample;
            hr = reader->ReadSample(
                MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                0,
                &streamIndex,
                &flags,
                &timestamp,
                &sample);

            if (FAILED(hr))
            {
                mediaSource->Shutdown();
                MFShutdown();
                return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
            }

            if ((flags & MF_SOURCE_READERF_STREAMTICK) != 0 || !sample)
            {
                continue;
            }

            ComPtr<IMFMediaBuffer> buffer;
            hr = sample->ConvertToContiguousBuffer(&buffer);
            if (FAILED(hr))
            {
                continue;
            }

            BYTE* data = nullptr;
            DWORD maxLength = 0;
            DWORD currentLength = 0;
            hr = buffer->Lock(&data, &maxLength, &currentLength);
            if (FAILED(hr))
            {
                continue;
            }

            auto expectedLength = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
            if (currentLength >= expectedLength)
            {
                result.SourceSize = { static_cast<int>(width), static_cast<int>(height) };
                result.RowPitch = width * 4;
                result.BgraPixels.assign(data, data + expectedLength);
                buffer->Unlock();
                mediaSource->Shutdown();
                MFShutdown();
                return PingCaptureSuccess;
            }

            buffer->Unlock();
        }

        mediaSource->Shutdown();
        MFShutdown();
        return PingCaptureNoCamera;
    }

    int CaptureCameraFrames(int durationMs, int framesPerSecond, std::vector<CameraFrameResult>& result)
    {
        result.clear();
        if (durationMs <= 0 || framesPerSecond <= 0)
        {
            return PingCaptureNoCamera;
        }

        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        IMFActivate** devices = nullptr;
        UINT32 deviceCount = 0;
        hr = EnumerateVideoDevices(&devices, &deviceCount);
        if (FAILED(hr) || deviceCount == 0)
        {
            ReleaseDevices(devices, deviceCount);
            MFShutdown();
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        ComPtr<IMFMediaSource> mediaSource;
        hr = devices[0]->ActivateObject(IID_PPV_ARGS(&mediaSource));
        ReleaseDevices(devices, deviceCount);
        if (FAILED(hr))
        {
            MFShutdown();
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
        }

        ComPtr<IMFSourceReader> reader;
        hr = MFCreateSourceReaderFromMediaSource(mediaSource.Get(), nullptr, &reader);
        if (FAILED(hr))
        {
            mediaSource->Shutdown();
            MFShutdown();
            return PingCaptureNoCamera;
        }

        ComPtr<IMFMediaType> desiredType;
        hr = MFCreateMediaType(&desiredType);
        if (SUCCEEDED(hr)) hr = desiredType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = desiredType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
        if (SUCCEEDED(hr))
        {
            hr = reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, desiredType.Get());
        }
        if (FAILED(hr))
        {
            mediaSource->Shutdown();
            MFShutdown();
            return PingCaptureNoCamera;
        }

        ComPtr<IMFMediaType> currentType;
        hr = reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_VIDEO_STREAM, &currentType);
        UINT32 width = 0;
        UINT32 height = 0;
        if (SUCCEEDED(hr))
        {
            hr = MFGetAttributeSize(currentType.Get(), MF_MT_FRAME_SIZE, &width, &height);
        }
        if (FAILED(hr) || width == 0 || height == 0)
        {
            mediaSource->Shutdown();
            MFShutdown();
            return PingCaptureNoCamera;
        }

        int frameCount = std::max(1, (durationMs * framesPerSecond + 999) / 1000);
        result.reserve(static_cast<size_t>(frameCount));
        auto startedAt = std::chrono::steady_clock::now();

        for (;;)
        {
            auto now = std::chrono::steady_clock::now();
            auto elapsedMs = static_cast<int>(std::chrono::duration_cast<std::chrono::milliseconds>(now - startedAt).count());
            if (elapsedMs >= durationMs)
            {
                break;
            }

            DWORD streamIndex = 0;
            DWORD flags = 0;
            LONGLONG timestamp = 0;
            ComPtr<IMFSample> sample;
            hr = reader->ReadSample(
                MF_SOURCE_READER_FIRST_VIDEO_STREAM,
                0,
                &streamIndex,
                &flags,
                &timestamp,
                &sample);
            if (FAILED(hr))
            {
                mediaSource->Shutdown();
                MFShutdown();
                return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoCamera;
            }

            if ((flags & MF_SOURCE_READERF_STREAMTICK) != 0 || !sample)
            {
                continue;
            }

            ComPtr<IMFMediaBuffer> buffer;
            hr = sample->ConvertToContiguousBuffer(&buffer);
            if (FAILED(hr))
            {
                continue;
            }

            BYTE* data = nullptr;
            DWORD maxLength = 0;
            DWORD currentLength = 0;
            hr = buffer->Lock(&data, &maxLength, &currentLength);
            if (FAILED(hr))
            {
                continue;
            }

            auto expectedLength = static_cast<size_t>(width) * static_cast<size_t>(height) * 4;
            if (currentLength >= expectedLength)
            {
                auto scheduledIndex = std::min(
                    frameCount - 1,
                    std::max(0, (elapsedMs * framesPerSecond) / 1000));
                if (static_cast<int>(result.size()) <= scheduledIndex)
                {
                    CameraFrameResult frame{};
                    frame.SourceSize = { static_cast<int>(width), static_cast<int>(height) };
                    frame.RowPitch = width * 4;
                    frame.BgraPixels.assign(data, data + expectedLength);
                    result.push_back(std::move(frame));
                }
            }
            buffer->Unlock();
        }

        mediaSource->Shutdown();
        MFShutdown();
        return static_cast<int>(result.size()) >= frameCount ? PingCaptureSuccess : PingCaptureNoCamera;
    }

    int CaptureMicrophonePcm(int durationMs, AudioCaptureResult& result)
    {
        if (durationMs <= 0)
        {
            return PingCaptureNoMicrophone;
        }

        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoMicrophone;
        }

        IMFActivate** devices = nullptr;
        UINT32 deviceCount = 0;
        hr = EnumerateAudioDevices(&devices, &deviceCount);
        if (FAILED(hr) || deviceCount == 0)
        {
            ReleaseDevices(devices, deviceCount);
            MFShutdown();
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoMicrophone;
        }

        ComPtr<IMFMediaSource> mediaSource;
        hr = devices[0]->ActivateObject(IID_PPV_ARGS(&mediaSource));
        ReleaseDevices(devices, deviceCount);
        if (FAILED(hr))
        {
            MFShutdown();
            return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoMicrophone;
        }

        ComPtr<IMFSourceReader> reader;
        hr = MFCreateSourceReaderFromMediaSource(mediaSource.Get(), nullptr, &reader);
        if (FAILED(hr))
        {
            mediaSource->Shutdown();
            MFShutdown();
            return PingCaptureNoMicrophone;
        }

        constexpr UINT32 samplesPerSecond = 48'000;
        constexpr UINT32 channels = 1;
        constexpr UINT32 bitsPerSample = 16;
        constexpr UINT32 blockAlignment = channels * bitsPerSample / 8;
        constexpr UINT32 bytesPerSecond = samplesPerSecond * blockAlignment;

        ComPtr<IMFMediaType> desiredType;
        hr = MFCreateMediaType(&desiredType);
        if (SUCCEEDED(hr)) hr = desiredType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
        if (SUCCEEDED(hr)) hr = desiredType->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
        if (SUCCEEDED(hr)) hr = desiredType->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
        if (SUCCEEDED(hr)) hr = desiredType->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, samplesPerSecond);
        if (SUCCEEDED(hr)) hr = desiredType->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, bitsPerSample);
        if (SUCCEEDED(hr)) hr = desiredType->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, blockAlignment);
        if (SUCCEEDED(hr)) hr = desiredType->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, bytesPerSecond);
        if (SUCCEEDED(hr))
        {
            hr = reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM, nullptr, desiredType.Get());
        }
        if (FAILED(hr))
        {
            mediaSource->Shutdown();
            MFShutdown();
            return PingCaptureNoMicrophone;
        }

        size_t expectedBytes = static_cast<size_t>(bytesPerSecond) * static_cast<size_t>(durationMs) / 1000;
        result = { samplesPerSecond, channels, bitsPerSample, {} };
        result.PcmBytes.reserve(expectedBytes);

        for (int attempt = 0; result.PcmBytes.size() < expectedBytes && attempt < 240; ++attempt)
        {
            DWORD streamIndex = 0;
            DWORD flags = 0;
            LONGLONG timestamp = 0;
            ComPtr<IMFSample> sample;
            hr = reader->ReadSample(
                MF_SOURCE_READER_FIRST_AUDIO_STREAM,
                0,
                &streamIndex,
                &flags,
                &timestamp,
                &sample);
            if (FAILED(hr))
            {
                mediaSource->Shutdown();
                MFShutdown();
                return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoMicrophone;
            }

            if (!sample || (flags & MF_SOURCE_READERF_STREAMTICK) != 0)
            {
                continue;
            }

            ComPtr<IMFMediaBuffer> buffer;
            hr = sample->ConvertToContiguousBuffer(&buffer);
            if (FAILED(hr))
            {
                continue;
            }

            BYTE* data = nullptr;
            DWORD maxLength = 0;
            DWORD currentLength = 0;
            hr = buffer->Lock(&data, &maxLength, &currentLength);
            if (FAILED(hr))
            {
                continue;
            }

            auto remaining = expectedBytes - result.PcmBytes.size();
            auto copyLength = std::min<size_t>(remaining, currentLength);
            result.PcmBytes.insert(result.PcmBytes.end(), data, data + copyLength);
            buffer->Unlock();
        }

        mediaSource->Shutdown();
        MFShutdown();
        if (result.PcmBytes.size() < expectedBytes)
        {
            return PingCaptureNoMicrophone;
        }

        return PingCaptureSuccess;
    }
}
