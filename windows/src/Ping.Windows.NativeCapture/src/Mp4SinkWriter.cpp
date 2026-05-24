#include "PingCaptureEngine.h"

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

namespace
{
    HRESULT SetMediaTypeUInt32(IMFMediaType* mediaType, REFGUID key, UINT32 value)
    {
        return mediaType->SetUINT32(key, value);
    }
}

namespace Ping::Windows::NativeCapture
{
    int InitializeMp4SinkWriter(const wchar_t* outputPath, OutputLayout const& layout, int durationMs)
    {
        if (outputPath == nullptr || outputPath[0] == L'\0' || layout.Width <= 0 || layout.Height <= 0 || durationMs <= 0)
        {
            return PingCaptureEncoderFailure;
        }

        HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_LITE);
        if (FAILED(hr))
        {
            return PingCaptureEncoderFailure;
        }

        ComPtr<IMFSinkWriter> sinkWriter;
        hr = MFCreateSinkWriterFromURL(outputPath, nullptr, nullptr, &sinkWriter);
        if (FAILED(hr))
        {
            MFShutdown();
            return PingCaptureEncoderFailure;
        }

        ComPtr<IMFMediaType> outputType;
        hr = MFCreateMediaType(&outputType);
        if (SUCCEEDED(hr)) hr = outputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = outputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
        if (SUCCEEDED(hr)) hr = SetMediaTypeUInt32(outputType.Get(), MF_MT_AVG_BITRATE, 8'000'000);
        if (SUCCEEDED(hr)) hr = MFSetAttributeSize(outputType.Get(), MF_MT_FRAME_SIZE, layout.Width, layout.Height);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(outputType.Get(), MF_MT_FRAME_RATE, 30, 1);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(outputType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        if (SUCCEEDED(hr)) hr = outputType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);

        DWORD videoStreamIndex = 0;
        if (SUCCEEDED(hr))
        {
            hr = sinkWriter->AddStream(outputType.Get(), &videoStreamIndex);
        }

        ComPtr<IMFMediaType> inputType;
        if (SUCCEEDED(hr)) hr = MFCreateMediaType(&inputType);
        if (SUCCEEDED(hr)) hr = inputType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        if (SUCCEEDED(hr)) hr = inputType->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_ARGB32);
        if (SUCCEEDED(hr)) hr = MFSetAttributeSize(inputType.Get(), MF_MT_FRAME_SIZE, layout.Width, layout.Height);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(inputType.Get(), MF_MT_FRAME_RATE, 30, 1);
        if (SUCCEEDED(hr)) hr = MFSetAttributeRatio(inputType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        if (SUCCEEDED(hr)) hr = inputType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        if (SUCCEEDED(hr)) hr = sinkWriter->SetInputMediaType(videoStreamIndex, inputType.Get(), nullptr);
        if (SUCCEEDED(hr)) hr = sinkWriter->BeginWriting();

        if (sinkWriter)
        {
            sinkWriter->Finalize();
        }
        MFShutdown();

        // The sink writer is initialized here, but frame production, compositing, audio capture,
        // and sample submission still need Windows hardware verification before enabling success.
        return PingCaptureEncoderFailure;
    }
}
