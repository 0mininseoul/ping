#include "RecordingStream.h"
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <future>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

using namespace Ping::Windows::NativeCapture;
void VerifyStreamingClip(wchar_t const* path, void (*check)(bool, char const*));

namespace
{
    std::unique_ptr<MonitorCaptureResult> Screen(std::uint8_t blue = 40)
    {
        auto frame = std::make_unique<MonitorCaptureResult>();
        frame->SourceSize = {540, 304}; frame->RowPitch = 540 * 4;
        frame->BgraPixels.resize(540 * 304 * 4, blue);
        return frame;
    }
    std::unique_ptr<CameraFrameResult> Camera()
    {
        auto frame = std::make_unique<CameraFrameResult>();
        frame->SourceSize = {98, 98}; frame->RowPitch = 98 * 4;
        frame->BgraPixels.resize(98 * 98 * 4, 100);
        return frame;
    }
    OutputLayout Layout() { return {540, 304, 98, 428, 192, 540.0 / 304}; }

    struct SyntheticProvider final : IRecordingFrameProvider
    {
        BoundedRecordingBuffer Buffer{Layout()};
        int Reads = 0, Stops = 0, FailureAt = -1;
        bool ThrowAtFailure = false;
        HANDLE SignalAtFailure = nullptr;
        LONGLONG LastEnd = 0;
        int ReadFrame(LONGLONG time, LONGLONG duration, RecordingFramePacket& packet, HANDLE cancellation) override
        {
            auto index = Reads++;
            if (index == FailureAt)
            {
                if (SignalAtFailure) { SetEvent(SignalAtFailure); return PingCaptureCancelled; }
                if (ThrowAtFailure) throw std::runtime_error("owned fake source failed");
                return PingCaptureNoMicrophone;
            }
            LastEnd = time + duration;
            if (Buffer.PublishScreen(Screen(static_cast<std::uint8_t>(index)), time) != PingCaptureSuccess
                || Buffer.PublishCamera(Camera(), time) != PingCaptureSuccess) return PingCaptureCaptureFailure;
            auto start = static_cast<std::uint64_t>(time) * 48'000 / 10'000'000;
            auto end = static_cast<std::uint64_t>(time + duration) * 48'000 / 10'000'000;
            std::vector<std::uint8_t> audio(static_cast<size_t>(end - start) * 2);
            for (auto sample = start; sample < end; ++sample)
            {
                auto amplitude = sample < 48'000 ? 2'000 : 10'000;
                auto value = static_cast<std::int16_t>(amplitude * std::sin(sample * 440 * 2 * 3.141592653589793 / 48'000));
                std::memcpy(audio.data() + static_cast<size_t>(sample - start) * 2, &value, 2);
            }
            auto result = Buffer.PublishAudio(start, audio);
            if (result != PingCaptureSuccess) return result;
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
            return Buffer.ReadFrame(time, duration, packet, cancellation);
        }
        void Stop() noexcept override { ++Stops; Buffer.Close(); }
    };

    struct DrainingProvider final : IRecordingFrameProvider
    {
        SyntheticProvider Source;
        std::promise<void> StopEntered;
        std::mutex Mutex;
        std::condition_variable Changed;
        bool Release = false;
        std::atomic<bool> CallbackCleaned = false;
        bool CleanupApartmentInitialized = false;
        std::thread Worker;
        DrainingProvider() { Source.FailureAt = 2; }
        int ReadFrame(LONGLONG time, LONGLONG duration, RecordingFramePacket& packet, HANDLE cancellation) override
        {
            if (!Worker.joinable()) Worker = std::thread([this] {
                auto owned = Screen();
                std::unique_lock lock(Mutex);
                Changed.wait(lock, [this] { return Release; });
                owned.reset(); CallbackCleaned = true;
            });
            return Source.ReadFrame(time, duration, packet, cancellation);
        }
        void Stop() noexcept override
        {
            APTTYPE apartment{}; APTTYPEQUALIFIER qualifier{};
            CleanupApartmentInitialized = SUCCEEDED(CoGetApartmentType(&apartment, &qualifier));
            Source.Stop(); StopEntered.set_value(); if (Worker.joinable()) Worker.join();
        }
        void ReleaseCallback() { std::lock_guard lock(Mutex); Release = true; Changed.notify_all(); }
        ~DrainingProvider() { ReleaseCallback(); if (Worker.joinable()) Worker.join(); }
    };
}

void RecordingStreamChecks(wchar_t const* directory, void (*check)(bool, char const*))
{
    auto base = std::wstring(directory);
    BoundedRecordingBuffer buffer{Layout()};
    check(buffer.PublishScreen(Screen(), 0) == PingCaptureSuccess && buffer.PublishCamera(Camera(), 0) == PingCaptureSuccess,
        "bounded feed accepts normalized owned screen and camera");
    check(buffer.PublishAudio(0, std::vector<std::uint8_t>(3'200, 7)) == PingCaptureSuccess,
        "bounded audio starts on common sample clock");
    RecordingFramePacket packet;
    check(buffer.ReadFrame(0, 333'333, packet, nullptr) == PingCaptureSuccess && packet.Audio.size() == 3'198,
        "first frame reads exact fractional30fps PCM interval");
    auto held = packet.Screen;
    std::weak_ptr<MonitorCaptureResult const> first = held;
    auto peakBufferBytes = buffer.RetainedBytes();
    for (int i = 1; i <= 90; ++i)
    {
        buffer.PublishScreen(Screen(static_cast<std::uint8_t>(i)), i * 333'333LL);
        peakBufferBytes = std::max(peakBufferBytes, buffer.RetainedBytes());
    }
    check(held->BgraPixels.front() == 40 && peakBufferBytes <= 540 * 304 * 4 + 98 * 98 * 4 + 48'000,
        "slow consumer keeps immutable snapshot while feed retains one latest frame");
    packet = {}; held.reset();
    check(first.expired(), "replaced frame releases after last consumer reference");
    auto wrong = Screen(); wrong->SourceSize.Width = 541;
    check(buffer.PublishScreen(std::move(wrong), 31'000'000) == PingCaptureCaptureFailure,
        "source resize fails before accepting incompatible frame");
    check(buffer.ReadFrame(333'333, 333'333, packet, nullptr) == PingCaptureCaptureFailure,
        "producer error wakes reader and preserves failure");
    check(buffer.RetainedBytes() == 0, "failed feed promptly releases retained media");

    BoundedRecordingBuffer overflow{Layout()};
    check(overflow.PublishAudio(0, std::vector<std::uint8_t>(48'002)) == PingCaptureNoMicrophone && overflow.RetainedBytes() == 0,
        "halfsecond audio limit fails explicitly instead of growing or dropping speech");
    BoundedRecordingBuffer gap{Layout()};
    check(gap.PublishAudio(10, {1, 2}) == PingCaptureNoMicrophone,
        "audio sample gap fails instead of fabricating silence");
    BoundedRecordingBuffer oversized{Layout()};
    auto oversizedScreen = Screen(); oversizedScreen->BgraPixels.reserve(2 * 540 * 304 * 4);
    check(oversized.PublishScreen(std::move(oversizedScreen), 0) == PingCaptureCaptureFailure,
        "oversized retained allocation cannot hide behind normalized pixel length");
    BoundedRecordingBuffer future{Layout()};
    future.PublishScreen(Screen(), 1'000'000); future.PublishCamera(Camera(), 1'000'000);
    future.PublishAudio(0, std::vector<std::uint8_t>(3'200));
    check(future.ReadFrame(0, 333'333, packet, nullptr) == PingCaptureCaptureFailure,
        "future source frame cannot be relabeled with earlier video timestamp");
    BoundedRecordingBuffer stale{Layout()};
    stale.PublishScreen(Screen(), 0); stale.PublishCamera(Camera(), 0);
    stale.PublishAudio(0, std::vector<std::uint8_t>(32'000));
    for (int i = 0; i < 7; ++i) stale.ReadFrame(i * 333'333LL, 333'333, packet, nullptr);
    check(stale.ReadFrame(7 * 333'333LL, 333'333, packet, nullptr) == PingCaptureCaptureFailure,
        "stalled source fails rather than freezing entire recording");
    BoundedRecordingBuffer timeout{Layout()};
    check(timeout.ReadFrame(0, 333'333, packet, nullptr, 20) == PingCaptureCaptureFailure && timeout.RetainedBytes() == 0,
        "startup deadline releases feed instead of waiting forever");
    BoundedRecordingBuffer cancelled{Layout()};
    HANDLE event = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    std::atomic<bool> entered = false;
    auto waiting = std::async(std::launch::async, [&] {
        RecordingFramePacket waitingPacket; entered = true;
        return cancelled.ReadFrame(0, 333'333, waitingPacket, event);
    });
    while (!entered) std::this_thread::yield();
    check(waiting.wait_for(std::chrono::milliseconds(20)) == std::future_status::timeout,
        "reader waits for source readiness without producing fake media");
    SetEvent(event);
    check(waiting.wait_for(std::chrono::milliseconds(200)) == std::future_status::ready && waiting.get() == PingCaptureCancelled,
        "waiting reader observes owned cancellation event");
    CloseHandle(event);
    DrainingProvider draining;
    auto enteredStop = draining.StopEntered.get_future();
    auto drainingPath = base + L"\\drained-source.mp4";
    auto writing = std::async(std::launch::async, [&] { return WriteScreenFaceMp4Stream(drainingPath.c_str(), Layout(), draining, 3000); });
    auto reachedStop = enteredStop.wait_for(std::chrono::seconds(3)) == std::future_status::ready;
    auto waited = writing.wait_for(std::chrono::milliseconds(20)) == std::future_status::timeout;
    draining.ReleaseCallback();
    auto result = writing.get();
    check(reachedStop && waited && result == PingCaptureNoMicrophone && draining.Source.Stops == 1 && draining.CallbackCleaned,
        "writer return waits for owned source callback cleanup");
    check(draining.CleanupApartmentInitialized, "COM apartment remains initialized until source cleanup finishes");
    check(GetFileAttributesW(drainingPath.c_str()) == INVALID_FILE_ATTRIBUTES,
        "partial file is deleted after callback drain finishes");
    SyntheticProvider invalid;
    check(WriteScreenFaceMp4Stream((std::wstring(directory) + L"\\absent\\cannot-write.mp4").c_str(), Layout(), invalid, 3000) == PingCaptureEncoderFailure
        && invalid.Reads == 0 && invalid.Stops == 1,
        "encoder startup failure stops provider before requesting any sample");
    cancelled.Close();
    check(cancelled.PublishScreen(Screen(), 0) == PingCaptureCancelled,
        "closed feed rejects late source callbacks");

    SyntheticProvider success;
    check(WriteScreenFaceMp4Stream((base + L"\\synthetic-stream.mp4").c_str(), Layout(), success, 3000) == PingCaptureSuccess,
        "incremental writer encodes changing synthetic frames without session vectors");
    check(success.Reads == 90 && success.Stops == 1 && success.LastEnd == 30'000'000 && success.Buffer.RetainedBytes() == 0,
        "video and PCM share exact3second clock and source stops once");
    VerifyStreamingClip((base + L"\\synthetic-stream.mp4").c_str(), check);
    SyntheticProvider failed; failed.FailureAt = 2;
    auto failedPath = base + L"\\source-failed.mp4";
    check(WriteScreenFaceMp4Stream(failedPath.c_str(), Layout(), failed, 3000) == PingCaptureNoMicrophone && failed.Stops == 1
        && GetFileAttributesW(failedPath.c_str()) == INVALID_FILE_ATTRIBUTES,
        "late source failure drains provider and deletes partial encoded file");
    SyntheticProvider thrown; thrown.FailureAt = 2; thrown.ThrowAtFailure = true;
    auto thrownPath = base + L"\\source-threw.mp4";
    check(WriteScreenFaceMp4Stream(thrownPath.c_str(), Layout(), thrown, 3000) == PingCaptureCaptureFailure && thrown.Stops == 1
        && GetFileAttributesW(thrownPath.c_str()) == INVALID_FILE_ATTRIBUTES,
        "source exception still stops provider and deletes partial encoded file");
    SyntheticProvider stopped; stopped.FailureAt = 2;
    event = CreateEventW(nullptr, TRUE, FALSE, nullptr); stopped.SignalAtFailure = event;
    auto cancelledPath = base + L"\\stream-cancelled.mp4";
    check(WriteScreenFaceMp4Stream(cancelledPath.c_str(), Layout(), stopped, 3000, {}, event) == PingCaptureCancelled
        && stopped.Stops == 1 && GetFileAttributesW(cancelledPath.c_str()) == INVALID_FILE_ATTRIBUTES,
        "encoding cancellation stops provider before returning without partial output");
    CloseHandle(event);
    std::cout << "Measured feed retained allocation peak=" << peakBufferBytes << " (consumer/codec/device buffers excluded)\n";
}
