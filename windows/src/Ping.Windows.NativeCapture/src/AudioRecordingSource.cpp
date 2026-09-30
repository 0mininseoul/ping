#include "NativeRecordingSources.h"
#include "MicrophonePacketReader.h"
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <cstring>
#include <stdexcept>

using Microsoft::WRL::ComPtr;

namespace Ping::Windows::NativeCapture
{
    namespace
    {
        struct Apartment
        {
            HRESULT Result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
            ~Apartment() { if (SUCCEEDED(Result)) CoUninitialize(); }
        };
        struct AudioSession
        {
            ComPtr<IAudioClient> Client;
            HANDLE Event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
            bool Started = false;
            ~AudioSession() { if (Started) Client->Stop(); Client.Reset(); if (Event) CloseHandle(Event); }
        };
        class AudioSource final : public RecordingSourceWorker
        {
        public:
            AudioSource(std::shared_ptr<RecordingSourceState> state, std::wstring endpoint)
                : RecordingSourceWorker(std::move(state)), endpoint_(std::move(endpoint)) {}
            int Run(HANDLE stop) override
            {
                Apartment apartment;
                if (FAILED(apartment.Result)) return PingCaptureNoMicrophone;
                ComPtr<IMMDeviceEnumerator> enumerator;
                auto hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator));
                ComPtr<IMMDevice> device;
                if (SUCCEEDED(hr)) hr = endpoint_.empty() ? enumerator->GetDefaultAudioEndpoint(eCapture, eCommunications, &device)
                    : enumerator->GetDevice(endpoint_.c_str(), &device);
                AudioSession owned;
                if (SUCCEEDED(hr)) hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(owned.Client.GetAddressOf()));
                WAVEFORMATEX format{};
                format.wFormatTag = WAVE_FORMAT_PCM; format.nChannels = 1; format.nSamplesPerSec = 48'000;
                format.wBitsPerSample = 16; format.nBlockAlign = 2; format.nAvgBytesPerSec = 96'000;
                if (SUCCEEDED(hr)) hr = owned.Client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                    AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                    1'000'000, 0, &format, nullptr);
                if (SUCCEEDED(hr) && !owned.Event) hr = E_OUTOFMEMORY;
                if (SUCCEEDED(hr)) hr = owned.Client->SetEventHandle(owned.Event);
                ComPtr<IAudioCaptureClient> capture;
                if (SUCCEEDED(hr)) hr = owned.Client->GetService(IID_PPV_ARGS(&capture));
                if (SUCCEEDED(hr)) hr = owned.Client->Start();
                if (FAILED(hr)) return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoMicrophone;
                owned.Started = true;
                HANDLE events[]{stop, owned.Event};
                bool firstPacket = true;
                while (true)
                {
                    auto wait = WaitForMultipleObjects(2, events, FALSE, 1000);
                    if (wait == WAIT_OBJECT_0) return PingCaptureSuccess;
                    if (wait != WAIT_OBJECT_0 + 1) return PingCaptureNoMicrophone;
                    auto result = DrainMicrophonePackets(*capture.Get(), State, stop, firstPacket);
                    if (result != PingCaptureSuccess) return result;
                }
            }
        private: std::wstring endpoint_;
        };
    }
    std::unique_ptr<IRecordingSource> MakeAudioRecordingSource(std::shared_ptr<RecordingSourceState> state, std::wstring endpoint)
    { return std::make_unique<AudioSource>(std::move(state), std::move(endpoint)); }
}
