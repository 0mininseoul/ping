#include "MicrophoneIdentity.h"
#include <functiondiscoverykeys_devpkey.h>
#include <memory>
#include <string>
#include <algorithm>

using namespace Ping::Windows::NativeCapture;
using Microsoft::WRL::ComPtr;

namespace
{
    constexpr int MaximumIdentityCapacity = 32768;
    struct Apartment
    {
        HRESULT Result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        ~Apartment() { if (SUCCEEDED(Result)) CoUninitialize(); }
    };
    struct Property
    {
        PROPVARIANT Value{};
        ~Property() { PropVariantClear(&Value); }
    };
    int Failure(HRESULT hr) { return hr == E_ACCESSDENIED ? PingCaptureAccessDenied : PingCaptureNoMicrophone; }
    bool ValidCapacity(int capacity) { return capacity > 0 && capacity <= MaximumIdentityCapacity; }
}

extern "C" __declspec(dllexport)
int PingCapture_GetDefaultMicrophoneIdentity(wchar_t* endpointId, int endpointCapacity, wchar_t* instanceId, int instanceCapacity)
try
{
    if (endpointId && ValidCapacity(endpointCapacity)) endpointId[0] = 0;
    if (instanceId && ValidCapacity(instanceCapacity)) instanceId[0] = 0;
    if (!endpointId || !instanceId || !ValidCapacity(endpointCapacity) || !ValidCapacity(instanceCapacity))
        return PingCaptureNoMicrophone;
    Apartment apartment;
    if (FAILED(apartment.Result) && apartment.Result != RPC_E_CHANGED_MODE) return Failure(apartment.Result);
    ComPtr<IMMDevice> endpoint;
    auto hr = GetDefaultMicrophoneEndpoint(&endpoint);
    if (FAILED(hr) || !endpoint) return Failure(hr);
    DWORD state = 0;
    hr = endpoint->GetState(&state);
    if (FAILED(hr) || !(state & DEVICE_STATE_ACTIVE)) return Failure(hr);
    LPWSTR rawId = nullptr;
    hr = endpoint->GetId(&rawId);
    std::unique_ptr<wchar_t, decltype(&CoTaskMemFree)> ownedId(rawId, CoTaskMemFree);
    if (FAILED(hr) || !rawId || !rawId[0]) return Failure(hr);
    ComPtr<IPropertyStore> properties;
    hr = endpoint->OpenPropertyStore(STGM_READ, &properties);
    if (FAILED(hr) || !properties) return Failure(hr);
    Property instance;
    hr = properties->GetValue(PKEY_Device_InstanceId, &instance.Value);
    if (FAILED(hr)) return Failure(hr);
    if (instance.Value.vt != VT_LPWSTR || !instance.Value.pwszVal || !instance.Value.pwszVal[0]) return PingCaptureNoMicrophone;
    auto idLength = wcsnlen_s(rawId, MaximumIdentityCapacity);
    auto instanceLength = wcsnlen_s(instance.Value.pwszVal, MaximumIdentityCapacity);
    if (idLength >= static_cast<size_t>(endpointCapacity) || instanceLength >= static_cast<size_t>(instanceCapacity))
        return PingCaptureNoMicrophone;
    std::copy_n(rawId, idLength + 1, endpointId);
    std::copy_n(instance.Value.pwszVal, instanceLength + 1, instanceId);
    return PingCaptureSuccess;
}
catch (...) { return PingCaptureNoMicrophone; }
