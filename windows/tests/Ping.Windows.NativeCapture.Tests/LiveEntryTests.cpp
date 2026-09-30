#include "LiveRecording.h"
#include <atomic>
#include <future>
#include <iostream>
#include <string>

using namespace Ping::Windows::NativeCapture;
extern std::atomic<int> FixtureLiveMode, FixtureLiveStarted, FixtureLiveDrained, FixtureLegacyStarts, FixtureDrainEntered;
extern HANDLE FixtureDrainRelease;
extern std::atomic<LONGLONG> FixtureAudioDrift;
extern CaptureViewport FixtureViewport;

void LiveEntryChecks(wchar_t const* directory, void (*check)(bool, char const*))
{
    auto path = std::wstring(directory) + L"\\live-owned-sources.mp4";
    FixtureLiveMode = 1; FixtureLiveStarted = 0; FixtureLiveDrained = 0;
    double aspect = 0;
    auto result = PingCapture_RecordScreenFaceMp4V2(path.c_str(), 3000, 0, .32, 2, .6, .4, nullptr, &aspect);
    std::cout << "Live entry result=" << result << ", started=" << FixtureLiveStarted << ", drained=" << FixtureLiveDrained
        << ", fake audio clock drift100ns=" << FixtureAudioDrift << '\n';
    check(result == PingCaptureSuccess && GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES,
        "product V2 entry streams3second clip from owned synthetic producers");
    check(FixtureLiveStarted == 3 && FixtureLiveDrained == 3 && FixtureLegacyStarts == 0,
        "product entry drains all live sources and never calls whole-session collectors");
    check(aspect > 1.7 && aspect < 1.9 && FixtureViewport.Zoom == 2 && FixtureViewport.CenterX == .6 && FixtureViewport.CenterY == .4,
        "product entry forwards frozen viewport and output aspect through live factory");
    FixtureLiveMode = 2; FixtureLiveStarted = 0; FixtureLiveDrained = 0;
    path = std::wstring(directory) + L"\\live-startup-failure.mp4";
    check(PingCapture_RecordScreenFaceMp4V2(path.c_str(), 3000, 0, .32, 1, .5, .5, nullptr, &aspect) == PingCaptureNoCamera
        && FixtureLiveStarted == 3 && FixtureLiveDrained == 3 && GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES,
        "product startup error cancels and joins every source without output");

    FixtureLiveMode = 1; FixtureLiveStarted = 0; FixtureLiveDrained = 0; FixtureDrainEntered = 0;
    HANDLE cancellation = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    FixtureDrainRelease = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    path = std::wstring(directory) + L"\\live-cancelled.mp4";
    auto writing = std::async(std::launch::async, [&] {
        return PingCapture_RecordScreenFaceMp4V2(path.c_str(), 3000, 0, .32, 1, .5, .5, cancellation, &aspect);
    });
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (FixtureLiveStarted < 3 && std::chrono::steady_clock::now() < deadline) std::this_thread::sleep_for(std::chrono::milliseconds(5));
    SetEvent(cancellation);
    auto waited = writing.wait_for(std::chrono::milliseconds(30)) == std::future_status::timeout;
    SetEvent(FixtureDrainRelease);
    result = writing.get();
    CloseHandle(FixtureDrainRelease); FixtureDrainRelease = nullptr; CloseHandle(cancellation);
    check(waited && result == PingCaptureCancelled && FixtureLiveDrained == 3 && GetFileAttributesW(path.c_str()) == INVALID_FILE_ATTRIBUTES,
        "product cancellation waits for actual producer drain before returning");
    FixtureLiveMode = 0;
}
