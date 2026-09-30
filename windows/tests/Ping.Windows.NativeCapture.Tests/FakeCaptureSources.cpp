#include "PingCaptureEngine.h"
#include <atomic>

std::atomic<int> FixtureSourceStarts{0};
namespace Ping::Windows::NativeCapture
{
    int CaptureOneMonitorFrame(int, MonitorCaptureResult&) { ++FixtureSourceStarts; return PingCaptureNoMonitor; }
    int CaptureMonitorFrames(int, int, int, std::vector<MonitorCaptureResult>&) { ++FixtureSourceStarts; return PingCaptureNoMonitor; }
    int CaptureCameraFrames(int, int, std::vector<CameraFrameResult>&) { ++FixtureSourceStarts; return PingCaptureNoCamera; }
    int CaptureMicrophonePcm(int, AudioCaptureResult&) { ++FixtureSourceStarts; return PingCaptureNoMicrophone; }
}
