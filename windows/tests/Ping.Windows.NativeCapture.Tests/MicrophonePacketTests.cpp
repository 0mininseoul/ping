#include "MicrophonePacketReader.h"
#include <wrl/implements.h>

using namespace Ping::Windows::NativeCapture;
using Microsoft::WRL::ComPtr;

namespace
{
    class PacketClient final : public Microsoft::WRL::RuntimeClass<Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IAudioCaptureClient>
    {
    public:
        bool Locked = false, Done = false;
        int Releases = 0, QueriesWhileLocked = 0;
        DWORD Flags = AUDCLNT_BUFFERFLAGS_SILENT;
        UINT32 ReleasedFrames = 0;
        STDMETHODIMP GetNextPacketSize(UINT32* frames) override
        {
            if (Locked) ++QueriesWhileLocked;
            *frames = Done ? 0 : 480; return S_OK;
        }
        STDMETHODIMP GetBuffer(BYTE** data, UINT32* frames, DWORD* flags, UINT64* position, UINT64* qpc) override
        {
            if (Done) { *frames = 0; return AUDCLNT_S_BUFFER_EMPTY; }
            if (Locked) return AUDCLNT_E_OUT_OF_ORDER;
            Locked = true; *data = nullptr; *frames = 480; *flags = Flags;
            *position = 100; *qpc = 1'000'000;
            return S_OK;
        }
        STDMETHODIMP ReleaseBuffer(UINT32 frames) override
        {
            if (!Locked) return AUDCLNT_E_OUT_OF_ORDER;
            ++Releases; ReleasedFrames = frames; Locked = false;
            if (frames == 480) Done = true;
            return S_OK;
        }
    };
}

void MicrophonePacketChecks(void (*check)(bool, char const*))
{
    auto layout = CreateScreenFaceLayout({960, 540}, .32, 540);
    auto state = std::make_shared<RecordingSourceState>(layout, 3000);
    auto client = Microsoft::WRL::Make<PacketClient>();
    bool first = true;
    check(DrainMicrophonePackets(*client.Get(), state, nullptr, first) == PingCaptureSuccess
        && client->Releases == 1 && client->QueriesWhileLocked == 0 && client->ReleasedFrames == 480,
        "microphone packet releases before querying next packet and accepts reported silence");
    client = Microsoft::WRL::Make<PacketClient>(); client->Flags = AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR;
    first = true;
    check(DrainMicrophonePackets(*client.Get(), state, nullptr, first) == PingCaptureNoMicrophone
        && client->Releases == 1 && !client->Locked && client->ReleasedFrames == 0,
        "invalid microphone timestamp releases unread buffer before failure");
    client = Microsoft::WRL::Make<PacketClient>(); client->Flags = 0;
    first = true;
    check(DrainMicrophonePackets(*client.Get(), state, nullptr, first) == PingCaptureNoMicrophone && client->Releases == 1,
        "missing microphone data cannot be fabricated as successful silence");
    client = Microsoft::WRL::Make<PacketClient>(); client->Flags |= AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY;
    first = false;
    check(DrainMicrophonePackets(*client.Get(), state, nullptr, first) == PingCaptureNoMicrophone && client->Releases == 1,
        "microphone discontinuity after startup fails explicitly");
}
