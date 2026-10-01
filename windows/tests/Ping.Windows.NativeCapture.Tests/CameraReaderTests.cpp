#include "CameraReaderSession.h"
#include <mfapi.h>
#include <atomic>
#include <future>
#include <string>

using namespace Ping::Windows::NativeCapture;
namespace
{
    struct Apartment { Apartment() { CoInitializeEx(nullptr, COINIT_MULTITHREADED); } ~Apartment() { CoUninitialize(); } };
    struct Foundation { Foundation() { MFStartup(MF_VERSION); } ~Foundation() { MFShutdown(); } };
    struct Event { HANDLE Handle = CreateEventW(nullptr, TRUE, FALSE, nullptr); ~Event() { CloseHandle(Handle); } };
}
void CameraReaderChecks(wchar_t const* directory, void (*check)(bool, char const*))
{
    Apartment apartment; Foundation foundation;
    auto path = std::wstring(directory) + L"\\synthetic-screen-face.mp4";
    Event entered, release, failed;
    std::atomic<int> frames{0}, errors{0}; std::atomic<bool> valid{true};
    auto token = std::make_shared<int>(1); std::weak_ptr<int> retained = token;
    CameraReaderSession reader(32, [&, token](std::unique_ptr<CameraFrameResult> frame, LONGLONG qpc)
    {
        if (!frame || frame->SourceSize.Width != 32 || frame->SourceSize.Height != 32
            || frame->RowPitch != 128 || frame->BgraPixels.size() != 4096 || qpc < 0) valid = false;
        ++frames; SetEvent(entered.Handle);
        if (WaitForSingleObject(release.Handle, 5000) != WAIT_OBJECT_0) return PingCaptureCaptureFailure;
        return PingCaptureSuccess;
    }, [&](int error) { errors = error; SetEvent(failed.Handle); });
    token.reset();
    check(SUCCEEDED(reader.InitializeReader([&](IMFAttributes* attributes, IMFSourceReader** result)
        { return MFCreateSourceReaderFromURL(path.c_str(), attributes, result); })),
        "actual async camera reader initializes from owned synthetic MP4");
    check(SUCCEEDED(reader.Start()), "actual camera reader starts asynchronous RGB32 decoding");
    auto wait = WaitForSingleObject(entered.Handle, 3000);
    if (wait != WAIT_OBJECT_0) SetEvent(release.Handle);
    check(wait == WAIT_OBJECT_0 && frames > 0 && valid && !retained.expired(),
        "actual MF callback delivers normalized owned face and retains callback state");
    check(FAILED(reader.Start()), "inflight camera reader cannot issue a second recording start");
    std::promise<void> closing;
    auto closed = std::async(std::launch::async, [&] { Apartment closeApartment; closing.set_value(); reader.Close(); });
    closing.get_future().wait();
    auto blocked = closed.wait_for(std::chrono::milliseconds(30)) == std::future_status::timeout;
    SetEvent(release.Handle);
    auto finished = closed.wait_for(std::chrono::seconds(3)) == std::future_status::ready;
    closed.get();
    check(blocked && finished && valid, "camera close waits active actual callback then actual Flush completion");
    auto stoppedFrames = frames.load(); std::this_thread::sleep_for(std::chrono::milliseconds(30));
    check(frames == stoppedFrames && retained.expired(), "closed camera reader rejects later media and releases publisher lifetime");
    reader.Close(); check(FAILED(reader.Start()), "closed camera reader cannot restart a disposed native session");

    Event ended; std::atomic<int> decoded{0}, endError{0}; std::atomic<LONGLONG> last{-1}; std::atomic<bool> monotonic{true};
    CameraReaderSession sequential(16, [&](auto frame, LONGLONG qpc)
    {
        if (!frame || qpc < last.load()) monotonic = false;
        last = qpc; ++decoded; return PingCaptureSuccess;
    }, [&](int error) { endError = error; SetEvent(ended.Handle); });
    check(SUCCEEDED(sequential.InitializeReader([&](auto attributes, auto result)
        { return MFCreateSourceReaderFromURL(path.c_str(), attributes, result); })) && SUCCEEDED(sequential.Start()),
        "camera session reads repeated actual decoder callbacks");
    check(WaitForSingleObject(ended.Handle, 5000) == WAIT_OBJECT_0 && decoded >= 80 && monotonic && endError == PingCaptureNoCamera,
        "camera file EOS propagates terminal source failure after monotonic actual frames");
    sequential.Close();

    CameraReaderSession denied(16, [](auto, auto) { return PingCaptureSuccess; }, [](int) {});
    check(denied.InitializeReader([](auto, auto) { return E_ACCESSDENIED; }) == E_ACCESSDENIED && FAILED(denied.Start()),
        "failed reader initialization cannot start or fabricate camera samples");
    denied.Close();

    Event rejected; std::atomic<int> rejectedFrames{0}, rejectedErrors{0}, rejectedCode{0};
    CameraReaderSession rejecting(16, [&](auto, auto) { ++rejectedFrames; return PingCaptureCancelled; },
        [&](int error) { ++rejectedErrors; rejectedCode = error; SetEvent(rejected.Handle); });
    check(SUCCEEDED(rejecting.InitializeReader([&](auto attributes, auto result)
        { return MFCreateSourceReaderFromURL(path.c_str(), attributes, result); })) && SUCCEEDED(rejecting.Start()),
        "owned camera decoder starts with cancellable frame consumer");
    auto rejectedWait = WaitForSingleObject(rejected.Handle, 3000); rejecting.Close();
    check(rejectedWait == WAIT_OBJECT_0 && rejectedFrames == 1 && rejectedErrors == 1 && rejectedCode == PingCaptureCancelled,
        "consumer cancellation propagates once and stops requesting further camera samples");

    Event thrown; std::atomic<int> thrownCode{0};
    CameraReaderSession throwing(16, [](auto, auto) -> int { throw std::runtime_error("fixture consumer failed"); },
        [&](int error) { thrownCode = error; SetEvent(thrown.Handle); });
    check(SUCCEEDED(throwing.InitializeReader([&](auto attributes, auto result)
        { return MFCreateSourceReaderFromURL(path.c_str(), attributes, result); })) && SUCCEEDED(throwing.Start()),
        "owned camera decoder starts with fallible frame consumer");
    auto thrownWait = WaitForSingleObject(thrown.Handle, 3000); throwing.Close();
    check(thrownWait == WAIT_OBJECT_0 && thrownCode == PingCaptureNoCamera,
        "camera consumer exception becomes terminal error without crossing COM callback ABI");
}
