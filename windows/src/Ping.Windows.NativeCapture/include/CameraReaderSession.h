#pragma once
#include "PingCaptureEngine.h"
#include <mfidl.h>
#include <mfreadwrite.h>
#include <functional>
#include <memory>

namespace Ping::Windows::NativeCapture
{
    class CameraReaderSession
    {
    public:
        using Publisher = std::function<int(std::unique_ptr<CameraFrameResult>, LONGLONG)>;
        using Failure = std::function<void(int)>;
        using ReaderFactory = std::function<HRESULT(IMFAttributes*, IMFSourceReader**)>;
        CameraReaderSession(int faceDiameter, Publisher publish, Failure fail);
        ~CameraReaderSession();
        CameraReaderSession(CameraReaderSession const&) = delete;
        CameraReaderSession& operator=(CameraReaderSession const&) = delete;
        HRESULT InitializeReader(ReaderFactory const& create);
        HRESULT Start();
        // Publishers signal failure; the owner closes after the callback has returned.
        void Close() noexcept;
    private:
        struct Impl;
        std::unique_ptr<Impl> impl_;
    };
}
