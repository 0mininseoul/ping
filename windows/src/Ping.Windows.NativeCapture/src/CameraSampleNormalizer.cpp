#include "CameraSampleNormalizer.h"
#include "CapturePixelView.h"
#include <mfapi.h>
#include <mferror.h>
#include <algorithm>
#include <limits>

using Microsoft::WRL::ComPtr;

namespace Ping::Windows::NativeCapture
{
    namespace
    {
        struct LockedBuffer
        {
            ComPtr<IMFMediaBuffer> Buffer;
            ComPtr<IMF2DBuffer2> TwoD;
            bool Locked = false;
            HRESULT Unlock()
            {
                if (!Locked) return S_OK;
                Locked = false;
                return TwoD ? TwoD->Unlock2D() : Buffer->Unlock();
            }
            ~LockedBuffer() { Unlock(); }
        };
        bool ResolveTimestamp(IMFSample* sample, LONGLONG sourceTime, LONGLONG arrival,
            CameraSampleState& state, LONGLONG& timestamp)
        {
            UINT64 deviceTime = 0;
            auto hr = sample->GetUINT64(MFSampleExtension_DeviceTimestamp, &deviceTime);
            if (SUCCEEDED(hr))
            {
                if (deviceTime > INT64_MAX) return false;
                timestamp = static_cast<LONGLONG>(deviceTime);
            }
            else
            {
                if (hr != MF_E_ATTRIBUTENOTFOUND || sourceTime < 0) return false;
                if (!state.SampleOffset) state.SampleOffset = arrival - sourceTime;
                auto offset = *state.SampleOffset;
                if ((offset > 0 && sourceTime > INT64_MAX - offset) || (offset < 0 && sourceTime < -offset)) return false;
                timestamp = sourceTime + offset;
            }
            if (state.LastTimestamp && timestamp < *state.LastTimestamp) return false;
            state.LastTimestamp = timestamp;
            return true;
        }
    }

    int NormalizeCameraSample(IMFMediaType* type, IMFSample* sample, int diameter,
        LONGLONG sourceTime, LONGLONG arrival, CameraSampleState& state,
        std::unique_ptr<CameraFrameResult>& output, LONGLONG& outputQpc)
    {
        output.reset(); outputQpc = 0;
        if (!type || !sample || diameter <= 0 || diameter > 540 || arrival < 0) return PingCaptureNoCamera;
        UINT32 width = 0, height = 0, rotation = 0;
        if (FAILED(MFGetAttributeSize(type, MF_MT_FRAME_SIZE, &width, &height))
            || width == 0 || height == 0 || width > 32768 || height > 32768) return PingCaptureNoCamera;
        GUID subtype{}, major{};
        if (FAILED(type->GetGUID(MF_MT_SUBTYPE, &subtype)) || subtype != MFVideoFormat_RGB32
            || FAILED(type->GetGUID(MF_MT_MAJOR_TYPE, &major)) || major != MFMediaType_Video) return PingCaptureNoCamera;
        auto rotationResult = type->GetUINT32(MF_MT_VIDEO_ROTATION, &rotation);
        if ((FAILED(rotationResult) && rotationResult != MF_E_ATTRIBUTENOTFOUND)
            || (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270)) return PingCaptureNoCamera;
        if (state.InputSize && (state.InputSize->Width != static_cast<int>(width) || state.InputSize->Height != static_cast<int>(height)))
            return PingCaptureNoCamera;
        auto next = state;
        LONGLONG timestamp = 0;
        if (!ResolveTimestamp(sample, sourceTime, arrival, next, timestamp)) return PingCaptureNoCamera;
        DWORD count = 0;
        if (FAILED(sample->GetBufferCount(&count)) || count != 1) return PingCaptureNoCamera;
        LockedBuffer owned;
        if (FAILED(sample->GetBufferByIndex(0, &owned.Buffer))) return PingCaptureNoCamera;
        BYTE* begin = nullptr; BYTE* scanline = nullptr; DWORD length = 0; LONG stride = 0;
        HRESULT hr;
        if (SUCCEEDED(owned.Buffer.As(&owned.TwoD)))
        {
            hr = owned.TwoD->Lock2DSize(MF2DBuffer_LockFlags_Read, &scanline, &stride, &begin, &length);
            if (FAILED(hr)) return PingCaptureNoCamera;
            owned.Locked = true;
        }
        else
        {
            hr = owned.Buffer->Lock(&begin, nullptr, &length);
            if (FAILED(hr)) return PingCaptureNoCamera;
            owned.Locked = true;
            UINT32 rawStride = 0;
            hr = type->GetUINT32(MF_MT_DEFAULT_STRIDE, &rawStride);
            if (SUCCEEDED(hr)) stride = static_cast<LONG>(rawStride);
            else if (hr == MF_E_ATTRIBUTENOTFOUND) hr = MFGetStrideForBitmapInfoHeader(MFVideoFormat_RGB32.Data1, width, &stride);
            scanline = begin;
            if (SUCCEEDED(hr) && stride < 0)
            {
                auto offset = static_cast<std::uint64_t>(-static_cast<std::int64_t>(stride)) * (height - 1);
                if (offset >= length) hr = E_FAIL;
                else if (scanline) scanline += static_cast<size_t>(offset);
            }
        }
        if (FAILED(hr) || !begin || !scanline || reinterpret_cast<std::uintptr_t>(scanline) < reinterpret_cast<std::uintptr_t>(begin))
            return PingCaptureNoCamera;
        auto offset = reinterpret_cast<std::uintptr_t>(scanline) - reinterpret_cast<std::uintptr_t>(begin);
        CapturePixelView view{begin, length, offset, stride, {static_cast<int>(width), static_cast<int>(height)}};
        auto side = static_cast<int>(std::min(width, height));
        auto frame = std::make_unique<CameraFrameResult>(); frame->SourceSize = {diameter, diameter};
        auto result = ResizeCapturePixels(view, {(static_cast<int>(width) - side) / 2, (static_cast<int>(height) - side) / 2, side, side},
            frame->SourceSize, frame->BgraPixels, frame->RowPitch, static_cast<int>(rotation));
        if (result != PingCaptureSuccess || FAILED(owned.Unlock())) return PingCaptureNoCamera;
        next.InputSize = view.SourceSize; state = next;
        output = std::move(frame); outputQpc = timestamp;
        return PingCaptureSuccess;
    }
}
