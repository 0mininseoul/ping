// Temporary build anchor for the native capture project.
// Real Windows Graphics Capture implementation will replace this in a later task.
extern "C" __declspec(dllexport) int PingWindowsNativeCapturePlaceholder()
{
    return 0;
}
