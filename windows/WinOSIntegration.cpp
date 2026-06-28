#include "WinOSIntegration.h"
#include <algorithm>
#include <comdef.h>
#include <dwmapi.h>

#pragma comment(lib, "wbemuuid.lib")
#pragma comment(lib, "dwmapi.lib")

#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif
#ifndef DWMWA_MICA_EFFECT
#define DWMWA_MICA_EFFECT 1029
#endif
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_COLOR_NONE
#define DWMWA_COLOR_NONE 0xFFFFFFFE
#endif

struct ACCENT_POLICY {
    DWORD AccentState;
    DWORD AccentFlags;
    DWORD GradientColor;
    DWORD AnimationId;
};

struct WINDOWCOMPOSITIONATTRIBDATA {
    DWORD Attribute;
    PVOID pvData;
    DWORD cbData;
};

typedef BOOL(WINAPI* pfnSetWindowCompositionAttribute)(HWND, WINDOWCOMPOSITIONATTRIBDATA*);

float WinOSIntegration::clamp01(float value) {
    return std::clamp(value, 0.0f, 1.0f);
}

WinOSIntegration& WinOSIntegration::instance() {
    static WinOSIntegration inst;
    return inst;
}

WinOSIntegration::WinOSIntegration() {
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    m_isWine = (hNtdll && GetProcAddress(hNtdll, "wine_get_version") != nullptr);

    CoInitializeEx(NULL, COINIT_MULTITHREADED);
    refreshMonitors();
    initWmi();

    if (!m_isWine) {
        m_brightnessThread = std::thread([this]() {
            HRESULT hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);

            while (true) {
                float level = 0.5f;
                {
                    std::unique_lock<std::mutex> lock(m_mutex);
                    m_cv.wait(lock, [this]() { return m_shutdown || m_hasNewBrightness; });
                    if (m_shutdown && !m_hasNewBrightness) {
                        break;
                    }
                    level = m_targetBrightness;
                    m_hasNewBrightness = false;
                }

                {
                    std::lock_guard<std::mutex> hwLock(m_hwMutex);
                    bool ddcSuccess = false;
                    if (!m_monitors.empty()) {
                        DWORD minB, curB, maxB;
                        if (GetMonitorBrightness(m_monitors[0].hPhysicalMonitor, &minB, &curB, &maxB) &&
                            maxB > minB) {
                            DWORD newB = minB + (DWORD)(level * (maxB - minB));
                            SetMonitorBrightness(m_monitors[0].hPhysicalMonitor, newB);
                            ddcSuccess = true;
                        }
                    }
                    if (!ddcSuccess) {
                        setBrightnessWmi(level);
                    }
                }
            }

            if (SUCCEEDED(hr)) {
                CoUninitialize();
            }
        });
    }
}

WinOSIntegration::~WinOSIntegration() {
    m_shutdown = true;
    m_cv.notify_one();
    if (m_brightnessThread.joinable()) {
        m_brightnessThread.join();
    }

    releaseMonitors();
    if (m_pVolume)       { m_pVolume->Release();       m_pVolume = nullptr; }
    if (m_pWbemServices) { m_pWbemServices->Release(); m_pWbemServices = nullptr; }
    if (m_pWbemLocator)  { m_pWbemLocator->Release();  m_pWbemLocator = nullptr; }
    CoUninitialize();
}

void WinOSIntegration::refreshMonitors() {
    if (m_isWine) return;
    releaseMonitors();
    HMONITOR hMonitor = MonitorFromWindow(GetDesktopWindow(), MONITOR_DEFAULTTOPRIMARY);
    DWORD numPhysicalMonitors;
    if (GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, &numPhysicalMonitors)) {
        m_monitors.resize(numPhysicalMonitors);
        if (!GetPhysicalMonitorsFromHMONITOR(hMonitor, numPhysicalMonitors, m_monitors.data())) {
            m_monitors.clear();
        }
    }
}

void WinOSIntegration::releaseMonitors() {
    if (!m_monitors.empty()) {
        DestroyPhysicalMonitors(static_cast<DWORD>(m_monitors.size()), m_monitors.data());
        m_monitors.clear();
    }
}

IAudioEndpointVolume* WinOSIntegration::getCachedVolumeControl() {
    if (m_pVolume) return m_pVolume;
    IMMDeviceEnumerator* pEnumerator = nullptr;
    IMMDevice* pDevice = nullptr;
    CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER,
                     __uuidof(IMMDeviceEnumerator), (void**)&pEnumerator);
    if (pEnumerator) {
        pEnumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &pDevice);
        if (pDevice) {
            pDevice->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_INPROC_SERVER,
                               nullptr, (void**)&m_pVolume);
            pDevice->Release();
        }
        pEnumerator->Release();
    }
    return m_pVolume;
}

float WinOSIntegration::getSystemVolume() {
    float volume = 0;
    if (auto* pVolume = getCachedVolumeControl())
        pVolume->GetMasterVolumeLevelScalar(&volume);
    return volume;
}

void WinOSIntegration::setSystemVolume(float level) {
    level = clamp01(level);
    if (auto* pVolume = getCachedVolumeControl())
        pVolume->SetMasterVolumeLevelScalar(level, nullptr);
}

bool WinOSIntegration::isMuted() {
    BOOL mute = FALSE;
    if (auto* pVolume = getCachedVolumeControl())
        pVolume->GetMute(&mute);
    return mute == TRUE;
}

void WinOSIntegration::setMuted(bool mute) {
    if (auto* pVolume = getCachedVolumeControl())
        pVolume->SetMute(mute, nullptr);
}

float WinOSIntegration::getSystemBrightness() {
    if (m_isWine) {
        return m_cachedBrightness;
    }
    ULONGLONG now = GetTickCount64();
    if (m_lastBrightnessQueryTime > 0 && (now - m_lastBrightnessQueryTime) < 3000) {
        return m_cachedBrightness;
    }

    float brightness = 0.5f;
    {
        std::lock_guard<std::mutex> hwLock(m_hwMutex);
        if (!m_monitors.empty()) {
            DWORD minB, curB, maxB;
            if (GetMonitorBrightness(m_monitors[0].hPhysicalMonitor, &minB, &curB, &maxB) &&
                maxB > minB) {
                brightness = (float)(curB - minB) / (float)(maxB - minB);
            } else {
                brightness = getBrightnessWmi();
            }
        } else {
            brightness = getBrightnessWmi();
        }
    }

    m_cachedBrightness = brightness;
    m_lastBrightnessQueryTime = now;
    return brightness;
}

void WinOSIntegration::setSystemBrightness(float level) {
    level = clamp01(level);
    m_cachedBrightness = level;
    m_lastBrightnessQueryTime = GetTickCount64();

    if (m_isWine) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_targetBrightness = level;
        m_hasNewBrightness = true;
    }
    m_cv.notify_one();
}

bool WinOSIntegration::initWmi() {
    if (m_isWine) return false;
    HRESULT hr = CoCreateInstance(CLSID_WbemLocator, 0, CLSCTX_INPROC_SERVER,
                                  IID_IWbemLocator, (LPVOID*)&m_pWbemLocator);
    if (FAILED(hr)) return false;

    hr = m_pWbemLocator->ConnectServer(
        _bstr_t(L"ROOT\\WMI"), NULL, NULL, 0, NULL, 0, 0, &m_pWbemServices);
    if (FAILED(hr)) return false;

    CoSetProxyBlanket(m_pWbemServices, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE,
                      NULL, RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE,
                      NULL, EOAC_NONE);
    m_wmiReady = true;
    return true;
}

float WinOSIntegration::getBrightnessWmi() {
    if (!m_wmiReady) return 0.5f;

    IEnumWbemClassObject* pEnumerator = NULL;
    HRESULT hr = m_pWbemServices->ExecQuery(
        _bstr_t("WQL"),
        _bstr_t("SELECT CurrentBrightness FROM WmiMonitorBrightness"),
        WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
        NULL, &pEnumerator);
    if (FAILED(hr)) return 0.5f;

    IWbemClassObject* pClassObject = NULL;
    ULONG uReturn = 0;
    float result = 0.5f;

    if (pEnumerator->Next(WBEM_INFINITE, 1, &pClassObject, &uReturn) == S_OK) {
        VARIANT vtProp;
        VariantInit(&vtProp);
        if (SUCCEEDED(pClassObject->Get(L"CurrentBrightness", 0, &vtProp, 0, 0))) {
            result = (float)vtProp.bVal / 100.0f;
            VariantClear(&vtProp);
        }
        pClassObject->Release();
    }
    pEnumerator->Release();
    return result;
}

void WinOSIntegration::setBrightnessWmi(float level) {
    if (!m_wmiReady) return;

    BYTE brightness = (BYTE)(level * 100.0f);

    IEnumWbemClassObject* pEnumerator = NULL;
    HRESULT hr = m_pWbemServices->ExecQuery(
        _bstr_t("WQL"),
        _bstr_t("SELECT * FROM WmiMonitorBrightnessMethods"),
        WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
        NULL, &pEnumerator);
    if (FAILED(hr)) return;

    IWbemClassObject* pClassObject = NULL;
    ULONG uReturn = 0;
    if (pEnumerator->Next(WBEM_INFINITE, 1, &pClassObject, &uReturn) == S_OK) {
        VARIANT vtPath;
        VariantInit(&vtPath);
        pClassObject->Get(L"__PATH", 0, &vtPath, 0, 0);

        IWbemClassObject* pInParamsDefinition = NULL;
        IWbemClassObject* pInParams = NULL;
        IWbemClassObject* pClass = NULL;

        m_pWbemServices->GetObject(_bstr_t(L"WmiMonitorBrightnessMethods"), 0, NULL, &pClass, NULL);
        if (pClass) {
            pClass->GetMethod(L"WmiSetBrightness", 0, &pInParamsDefinition, NULL);
            if (pInParamsDefinition) {
                pInParamsDefinition->SpawnInstance(0, &pInParams);
                VARIANT vtTimeout;
                VariantInit(&vtTimeout);
                vtTimeout.vt = VT_I4; vtTimeout.lVal = 1;
                pInParams->Put(L"Timeout", 0, &vtTimeout, 0);

                VARIANT vtBrightness;
                VariantInit(&vtBrightness);
                vtBrightness.vt = VT_UI1; vtBrightness.bVal = brightness;
                pInParams->Put(L"Brightness", 0, &vtBrightness, 0);

                m_pWbemServices->ExecMethod(vtPath.bstrVal,
                    _bstr_t(L"WmiSetBrightness"), 0, NULL, pInParams, NULL, NULL);

                pInParams->Release();
                pInParamsDefinition->Release();
            }
            pClass->Release();
        }
        VariantClear(&vtPath);
        pClassObject->Release();
    }
    pEnumerator->Release();
}

void WinOSIntegration::applyFrostedGlass(HWND hwnd)
{
    if (!hwnd) return;

    BOOL darkMode = TRUE;
    DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &darkMode, sizeof(darkMode));

    DWM_WINDOW_CORNER_PREFERENCE corner = DWMWCP_ROUND;
    DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corner, sizeof(corner));

    DWORD borderNone = DWMWA_COLOR_NONE;
    DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &borderNone, sizeof(borderNone));

    int backdrop = 3; 
    HRESULT hr = DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop, sizeof(backdrop));
    if (SUCCEEDED(hr)) {
        return;
    }

    BOOL mica = TRUE;
    hr = DwmSetWindowAttribute(hwnd, DWMWA_MICA_EFFECT, &mica, sizeof(mica));
    if (SUCCEEDED(hr)) {
        return;
    }

    HMODULE hUser = GetModuleHandleW(L"user32.dll");
    if (hUser) {
        pfnSetWindowCompositionAttribute setWindowCompositionAttribute = 
            (pfnSetWindowCompositionAttribute)GetProcAddress(hUser, "SetWindowCompositionAttribute");
        if (setWindowCompositionAttribute) {
            ACCENT_POLICY policy = {0};
            policy.AccentState = 4;
            policy.GradientColor = 0xC81E1E1E;
            policy.AccentFlags = 2;

            WINDOWCOMPOSITIONATTRIBDATA data = {0};
            data.Attribute = 19;
            data.pvData = &policy;
            data.cbData = sizeof(policy);

            setWindowCompositionAttribute(hwnd, &data);
        }
    }
}
