#include "LiveRecording.h"
#include "CaptureCallbackGate.h"
#include <atomic>
#include <future>
#include <iostream>

using namespace Ping::Windows::NativeCapture;

namespace
{
    class FailingSource final : public RecordingSourceWorker
    {
    public:
        FailingSource(std::shared_ptr<RecordingSourceState> state, std::atomic<int>& drained) : RecordingSourceWorker(std::move(state)), drained_(drained) {}
        int Run(HANDLE stop) override { State->Fail(PingCaptureNoCamera); WaitForSingleObject(stop, INFINITE); ++drained_; return PingCaptureSuccess; }
    private: std::atomic<int>& drained_;
    };

    std::unique_ptr<MonitorCaptureResult> Screen(OutputLayout layout)
    {
        auto frame = std::make_unique<MonitorCaptureResult>();
        frame->SourceSize = {layout.Width, layout.Height}; frame->RowPitch = layout.Width * 4;
        frame->BgraPixels.resize(static_cast<size_t>(frame->RowPitch) * layout.Height, 25);
        return frame;
    }
    std::unique_ptr<CameraFrameResult> Camera(OutputLayout layout)
    {
        auto frame = std::make_unique<CameraFrameResult>();
        frame->SourceSize = {layout.FaceDiameter, layout.FaceDiameter}; frame->RowPitch = layout.FaceDiameter * 4;
        frame->BgraPixels.resize(static_cast<size_t>(frame->RowPitch) * layout.FaceDiameter, 100);
        return frame;
    }
}

void LiveRecordingChecks(void (*check)(bool, char const*))
{
    auto gate = std::make_shared<CaptureCallbackGate>();
    std::promise<void> callbackEntered, callbackRelease;
    auto release = callbackRelease.get_future();
    auto callback = std::async(std::launch::async, [gate, &callbackEntered, &release] {
        auto lease = gate->Enter(); callbackEntered.set_value(); release.wait(); return static_cast<bool>(lease);
    });
    callbackEntered.get_future().wait();
    auto closing = std::async(std::launch::async, [gate] { gate->CloseAndDrain(); });
    auto waitedForCallback = closing.wait_for(std::chrono::milliseconds(20)) == std::future_status::timeout;
    callbackRelease.set_value(); callback.get(); closing.get();
    check(waitedForCallback && !static_cast<bool>(gate->Enter()),
        "source callback gate drains active callback and rejects late callback work");
    auto layout = CreateScreenFaceLayout({960, 540}, .32, 540);
    auto state = std::make_shared<RecordingSourceState>(layout, 3000, [] { return 2'000'000LL; });
    state->SubmitScreen(Screen(layout), 1'000'000);
    state->SubmitCamera(Camera(layout), 1'000'000);
    state->SubmitAudio(10, 1'000'000, std::vector<std::uint8_t>(960));
    HANDLE cancel = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    auto starting = std::async(std::launch::async, [&] { return state->WaitStart(cancel); });
    auto didWait = starting.wait_for(std::chrono::milliseconds(20)) == std::future_status::timeout;
    state->SubmitAudio(490, 1'100'000, std::vector<std::uint8_t>(3'200));
    auto started = starting.get();
    check(didWait && started == PingCaptureSuccess, "shared recording starts on next microphone packet after all sources are ready");
    RecordingFramePacket packet;
    check(state->ReadFrame(0, 333'333, packet, cancel) == PingCaptureSuccess && packet.Audio.size() == 3'198,
        "warmup audio is discarded and recording starts at sample zero");
    state->Close();
    check(state->SubmitCamera(Camera(layout), 1'200'000) == PingCaptureCancelled,
        "closed live state rejects late camera callback");
    CloseHandle(cancel);

    auto failing = std::make_shared<RecordingSourceState>(layout, 3000);
    std::atomic<int> drained = 0;
    std::vector<std::unique_ptr<IRecordingSource>> sources;
    sources.push_back(std::make_unique<FailingSource>(failing, drained));
    LiveRecordingProvider provider(failing, std::move(sources));
    check(provider.ReadFrame(0, 333'333, packet, nullptr) == PingCaptureNoCamera,
        "early source failure propagates through live provider without startup timeout");
    provider.Stop(); provider.Stop();
    check(drained == 1, "live provider signals and joins each source once on failure");
}
