#include "CameraSampleNormalizer.h"
#include <mfapi.h>
#include <mferror.h>
#include <limits>

using namespace Ping::Windows::NativeCapture;
using Microsoft::WRL::ComPtr;

namespace
{
    struct Apartment { ~Apartment() { CoUninitialize(); } };
    struct Foundation { ~Foundation() { MFShutdown(); } };
    ComPtr<IMFMediaType> Type(UINT32 width = 6, UINT32 height = 4, int stride = 32, UINT32 rotation = 0)
    {
        ComPtr<IMFMediaType> type;
        MFCreateMediaType(&type); type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
        type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        MFSetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, width, height);
        type->SetUINT32(MF_MT_DEFAULT_STRIDE, static_cast<UINT32>(stride));
        type->SetUINT32(MF_MT_VIDEO_ROTATION, rotation);
        return type;
    }
    ComPtr<IMFSample> Sample(bool twoD, bool bottomUp, DWORD length = 128)
    {
        ComPtr<IMFMediaBuffer> buffer;
        if (twoD) MFCreate2DMediaBuffer(6, 4, MFVideoFormat_RGB32.Data1, bottomUp, &buffer);
        else { MFCreateMemoryBuffer(length, &buffer); buffer->SetCurrentLength(length); }
        ComPtr<IMF2DBuffer2> image;
        BYTE* scanline = nullptr; BYTE* begin = nullptr; LONG stride = bottomUp ? -32 : 32; DWORD bytes = 0;
        if (twoD)
        {
            buffer.As(&image); image->Lock2DSize(MF2DBuffer_LockFlags_Write, &scanline, &stride, &begin, &bytes);
        }
        else { buffer->Lock(&begin, nullptr, &bytes); scanline = begin + (bottomUp ? 96 : 0); }
        if (length >= 128 || twoD)
            for (int y = 0; y < 4; ++y) for (int x = 0; x < 6; ++x)
            {
                auto pixel = scanline + y * stride + x * 4;
                pixel[0] = static_cast<BYTE>(x); pixel[1] = static_cast<BYTE>(y); pixel[2] = 20; pixel[3] = 12;
            }
        if (twoD) image->Unlock2D(); else buffer->Unlock();
        ComPtr<IMFSample> sample; MFCreateSample(&sample); sample->AddBuffer(buffer.Get());
        return sample;
    }
}

void CameraSampleChecks(void (*check)(bool, char const*))
{
    check(SUCCEEDED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)), "camera fixture owns COM apartment"); Apartment apartment;
    check(SUCCEEDED(MFStartup(MF_VERSION)), "camera fixture owns MF without activating a device"); Foundation foundation;
    std::unique_ptr<CameraFrameResult> frame; LONGLONG qpc = 0;
    for (bool twoD : {false, true}) for (bool bottomUp : {false, true})
    {
        auto type = Type(6, 4, bottomUp ? -32 : 32); auto sample = Sample(twoD, bottomUp); CameraSampleState state;
        sample->SetUINT64(MFSampleExtension_DeviceTimestamp, 7'000'000);
        auto result = NormalizeCameraSample(type.Get(), sample.Get(), 4, 1'000'000, 5'000'000, state, frame, qpc);
        check(result == PingCaptureSuccess && frame && qpc == 7'000'000 && frame->RowPitch == 16
            && frame->BgraPixels.size() == 64 && frame->BgraPixels[0] == 1 && frame->BgraPixels[1] == 0
            && frame->BgraPixels[60] == 4 && frame->BgraPixels[61] == 3 && frame->BgraPixels[3] == 255,
            twoD ? "actual MF2D buffer normalizes pitch and central square into owned face"
                 : "actual MF raw buffer normalizes signed stride and central square into owned face");
    }
    for (UINT32 rotation : {90u, 180u, 270u})
    {
        CameraSampleState state; auto type = Type(6, 4, 32, rotation); auto sample = Sample(false, false);
        check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 0, 100, state, frame, qpc) == PingCaptureSuccess
            && frame->BgraPixels[0] == (rotation == 90 || rotation == 180 ? 4 : 1)
            && frame->BgraPixels[1] == (rotation == 180 || rotation == 270 ? 3 : 0),
            "MF counterclockwise orientation is baked into square pixels");
    }
    CameraSampleState state; auto type = Type(); auto sample = Sample(false, false);
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 100, 1000, state, frame, qpc) == PingCaptureSuccess && qpc == 1000,
        "camera without device QPC calibrates sample clock once");
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 200, 5000, state, frame, qpc) == PingCaptureSuccess && qpc == 1100,
        "later camera sample follows source clock rather than callback arrival delay");
    sample->SetUINT64(MFSampleExtension_DeviceTimestamp, std::numeric_limits<UINT64>::max());
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 300, 6000, state, frame, qpc) == PingCaptureNoCamera && !frame,
        "invalid device QPC fails without fallback timestamp or output frame");
    sample->DeleteItem(MFSampleExtension_DeviceTimestamp); type->SetUINT32(MF_MT_VIDEO_ROTATION, 45);
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 300, 6000, state, frame, qpc) == PingCaptureNoCamera,
        "unsupported camera orientation is rejected before pixel conversion");
    type = Type(8, 4, 32);
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 300, 6000, state, frame, qpc) == PingCaptureNoCamera,
        "camera source resize cannot silently change the active recording format");
    CameraSampleState shortState; type = Type(); sample = Sample(false, false, 20);
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 0, 100, shortState, frame, qpc) == PingCaptureNoCamera && !frame,
        "truncated actual MF buffer fails before row reads");
    sample = Sample(false, false); type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 0, 100, shortState, frame, qpc) == PingCaptureNoCamera,
        "non-RGB camera frame cannot be read as BGRA");
    type = Type(); sample = Sample(false, false); CameraSampleState boundary;
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 0, 100, boundary, frame, qpc) == PingCaptureSuccess,
        "valid first sample establishes bounded camera format and clock");
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, INT64_MAX, 100, boundary, frame, qpc) == PingCaptureNoCamera,
        "camera timestamp offset addition cannot overflow signed clock");
    boundary = {}; check(NormalizeCameraSample(type.Get(), sample.Get(), 4, -1, 100, boundary, frame, qpc) == PingCaptureNoCamera,
        "missing device timestamp cannot calibrate a negative source time");
    sample->SetUINT64(MFSampleExtension_DeviceTimestamp, 10);
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 0, 100, boundary, frame, qpc) == PingCaptureSuccess,
        "device QPC initializes camera clock independently of source time");
    sample->SetUINT64(MFSampleExtension_DeviceTimestamp, 9);
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 0, 100, boundary, frame, qpc) == PingCaptureNoCamera && !frame,
        "camera clock reversal fails without relabeling frame time");
    sample->SetUINT32(MFSampleExtension_DeviceTimestamp, 11);
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 0, 100, boundary, frame, qpc) == PingCaptureNoCamera,
        "wrong device timestamp attribute type cannot silently use callback clock");
    sample->DeleteItem(MFSampleExtension_DeviceTimestamp); ComPtr<IMFMediaBuffer> extra;
    MFCreateMemoryBuffer(4, &extra); sample->AddBuffer(extra.Get());
    boundary = {};
    check(NormalizeCameraSample(type.Get(), sample.Get(), 4, 0, 100, boundary, frame, qpc) == PingCaptureNoCamera && !frame,
        "multi-buffer camera input fails without hidden fullframe contiguous copy");
}
