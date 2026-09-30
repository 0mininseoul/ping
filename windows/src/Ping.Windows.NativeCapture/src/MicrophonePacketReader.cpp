#include "MicrophonePacketReader.h"
#include <cstring>

namespace Ping::Windows::NativeCapture
{
    namespace
    {
        struct AudioPacket
        {
            IAudioCaptureClient& Capture;
            UINT32 Frames = 0;
            bool Acquired = false, Consumed = false;
            ~AudioPacket() { if (Acquired) Capture.ReleaseBuffer(Consumed ? Frames : 0); }
        };
    }
    int DrainMicrophonePackets(IAudioCaptureClient& capture, std::shared_ptr<RecordingSourceState> const& state,
        HANDLE stop, bool& firstPacket)
    {
        UINT32 pending = 0;
        if (FAILED(capture.GetNextPacketSize(&pending))) return PingCaptureNoMicrophone;
        while (pending)
        {
            if (stop && WaitForSingleObject(stop, 0) == WAIT_OBJECT_0) return PingCaptureCancelled;
            AudioPacket packet{capture};
            BYTE* data = nullptr; DWORD flags = 0; UINT64 devicePosition = 0, qpc = 0;
            auto hr = capture.GetBuffer(&data, &packet.Frames, &flags, &devicePosition, &qpc);
            if (FAILED(hr)) return PingCaptureNoMicrophone;
            if (hr == AUDCLNT_S_BUFFER_EMPTY) return PingCaptureSuccess;
            packet.Acquired = true;
            if (packet.Frames == 0 || packet.Frames > 24'000 || qpc > INT64_MAX
                || (flags & AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR)
                || (!firstPacket && (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY))) return PingCaptureNoMicrophone;
            firstPacket = false;
            std::vector<std::uint8_t> pcm(static_cast<size_t>(packet.Frames) * 2);
            if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT))
            {
                if (!data) return PingCaptureNoMicrophone;
                std::memcpy(pcm.data(), data, pcm.size());
            }
            packet.Consumed = true;
            auto result = state->SubmitAudio(devicePosition, static_cast<LONGLONG>(qpc), pcm);
            if (result != PingCaptureSuccess) return result;
            hr = capture.ReleaseBuffer(packet.Frames);
            packet.Acquired = false;
            if (FAILED(hr)) return PingCaptureNoMicrophone;
            if (FAILED(capture.GetNextPacketSize(&pending))) return PingCaptureNoMicrophone;
        }
        return PingCaptureSuccess;
    }
}
