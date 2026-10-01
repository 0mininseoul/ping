#include "MicrophoneIdentity.h"
#include <functiondiscoverykeys_devpkey.h>
#include <wrl/implements.h>
#include <cstring>
#include <string>

using namespace Ping::Windows::NativeCapture;
using Microsoft::WRL::ComPtr;
extern ComPtr<IMMDevice> FixtureMicrophoneEndpoint;
extern HRESULT FixtureMicrophoneResult;

namespace
{
    class Endpoint final : public Microsoft::WRL::RuntimeClass<Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IMMDevice, IPropertyStore>
    {
    public:
        DWORD State = DEVICE_STATE_ACTIVE;
        VARTYPE Type = VT_LPWSTR;
        HRESULT PropertyResult = S_OK;
        bool KeyRead = false, ReadOnly = false;
        std::wstring Id = L"{fixture-opaque-endpoint}", Instance = L"SWD\\MMDEVAPI\\fixture-instance";
        HRESULT STDMETHODCALLTYPE Activate(REFIID, DWORD, PROPVARIANT*, void**) override { return E_UNEXPECTED; }
        HRESULT STDMETHODCALLTYPE OpenPropertyStore(DWORD access, IPropertyStore** store) override
        { ReadOnly = access == STGM_READ; return QueryInterface(IID_PPV_ARGS(store)); }
        HRESULT STDMETHODCALLTYPE GetId(LPWSTR* id) override
        {
            *id = static_cast<LPWSTR>(CoTaskMemAlloc((Id.size() + 1) * sizeof(wchar_t)));
            if (!*id) return E_OUTOFMEMORY;
            std::memcpy(*id, Id.c_str(), (Id.size() + 1) * sizeof(wchar_t)); return S_OK;
        }
        HRESULT STDMETHODCALLTYPE GetState(DWORD* state) override { *state = State; return S_OK; }
        HRESULT STDMETHODCALLTYPE GetCount(DWORD*) override { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetAt(DWORD, PROPERTYKEY*) override { return E_NOTIMPL; }
        HRESULT STDMETHODCALLTYPE GetValue(REFPROPERTYKEY key, PROPVARIANT* property) override
        {
            KeyRead = IsEqualPropertyKey(key, PKEY_Device_InstanceId);
            PropVariantInit(property);
            if (FAILED(PropertyResult)) return PropertyResult;
            property->vt = Type;
            if (Type == VT_LPWSTR)
            {
                property->pwszVal = static_cast<LPWSTR>(CoTaskMemAlloc((Instance.size() + 1) * sizeof(wchar_t)));
                if (!property->pwszVal) return E_OUTOFMEMORY;
                std::memcpy(property->pwszVal, Instance.c_str(), (Instance.size() + 1) * sizeof(wchar_t));
            }
            return S_OK;
        }
        HRESULT STDMETHODCALLTYPE SetValue(REFPROPERTYKEY, REFPROPVARIANT) override { return E_UNEXPECTED; }
        HRESULT STDMETHODCALLTYPE Commit() override { return E_UNEXPECTED; }
    };
}

void MicrophoneIdentityChecks(void (*check)(bool, char const*))
{
    auto endpoint = Microsoft::WRL::Make<Endpoint>();
    FixtureMicrophoneEndpoint = endpoint; FixtureMicrophoneResult = S_OK;
    wchar_t id[128]{}, instance[128]{};
    check(PingCapture_GetDefaultMicrophoneIdentity(id, 128, instance, 128) == PingCaptureSuccess
        && id == endpoint->Id && instance == endpoint->Instance && endpoint->KeyRead && endpoint->ReadOnly,
        "microphone identity reads active endpoint and documented instance property without activation or ID rewriting");
    wchar_t shortBuffer[2]{L'x', L'x'};
    id[0] = L'x';
    check(PingCapture_GetDefaultMicrophoneIdentity(id, 128, shortBuffer, 2) == PingCaptureNoMicrophone && id[0] == 0 && shortBuffer[0] == 0,
        "insufficient identity buffers return no partial pair and never truncate an opaque ID");
    check(PingCapture_GetDefaultMicrophoneIdentity(nullptr, 128, instance, 128) == PingCaptureNoMicrophone
        && PingCapture_GetDefaultMicrophoneIdentity(id, 0, instance, 128) == PingCaptureNoMicrophone,
        "identity ABI rejects invalid caller buffers");
    endpoint->State = DEVICE_STATE_UNPLUGGED;
    check(PingCapture_GetDefaultMicrophoneIdentity(id, 128, instance, 128) == PingCaptureNoMicrophone,
        "unplugged selected microphone cannot be frozen as an active pair");
    endpoint->State = DEVICE_STATE_ACTIVE; endpoint->Type = VT_EMPTY;
    check(PingCapture_GetDefaultMicrophoneIdentity(id, 128, instance, 128) == PingCaptureNoMicrophone,
        "missing device-instance property cannot trigger ID parsing or default substitution");
    endpoint->Type = VT_UI4;
    check(PingCapture_GetDefaultMicrophoneIdentity(id, 128, instance, 128) == PingCaptureNoMicrophone,
        "wrong property type cannot be interpreted as a device ID");
    endpoint->Type = VT_LPWSTR; endpoint->PropertyResult = E_ACCESSDENIED;
    check(PingCapture_GetDefaultMicrophoneIdentity(id, 128, instance, 128) == PingCaptureAccessDenied,
        "endpoint property access denial retains its typed error");
    endpoint->PropertyResult = S_OK; endpoint->Instance.clear();
    check(PingCapture_GetDefaultMicrophoneIdentity(id, 128, instance, 128) == PingCaptureNoMicrophone,
        "empty instance property cannot select an arbitrary interface");
    FixtureMicrophoneEndpoint.Reset(); FixtureMicrophoneResult = HRESULT_FROM_WIN32(ERROR_NOT_FOUND);
    check(PingCapture_GetDefaultMicrophoneIdentity(id, 128, instance, 128) == PingCaptureNoMicrophone,
        "no communications endpoint is an explicit microphone failure");
}
