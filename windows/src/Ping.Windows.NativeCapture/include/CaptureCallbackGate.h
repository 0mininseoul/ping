#pragma once
#include <mutex>

namespace Ping::Windows::NativeCapture
{
    class CaptureCallbackGate
    {
    public:
        class Lease
        {
        public:
            Lease(std::mutex& mutex, bool const& closed) : lock_(mutex), active_(!closed) {}
            explicit operator bool() const { return active_; }
        private:
            std::unique_lock<std::mutex> lock_;
            bool active_;
        };
        Lease Enter() { return Lease(mutex_, closed_); }
        void CloseAndDrain() { std::lock_guard guard(mutex_); closed_ = true; }
    private:
        std::mutex mutex_;
        bool closed_ = false;
    };
}
