#pragma once

#include <windows.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <highlevelmonitorconfigurationapi.h>
#include <physicalmonitorenumerationapi.h>
#include <wbemidl.h>

#include <vector>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <atomic>

class WinOSIntegration {
public:
    static WinOSIntegration& instance();

    // Volume (0.0 - 1.0)
    float getSystemVolume();
    void setSystemVolume(float level);
    bool isMuted();
    void setMuted(bool mute);

    // Brightness (0.0 - 1.0)
    // Uses DDC/CI for external monitors, WMI for internal laptop panels
    float getSystemBrightness();
    void setSystemBrightness(float level);

    // Frosted glass integration (Acrylic/Mica)
    void applyFrostedGlass(HWND hwnd);

private:
    WinOSIntegration();
    ~WinOSIntegration();

    IAudioEndpointVolume* getCachedVolumeControl();
    IAudioEndpointVolume* m_pVolume = nullptr;

    // DDC/CI (external monitors)
    std::vector<PHYSICAL_MONITOR> m_monitors;
    void refreshMonitors();
    void releaseMonitors();

    // WMI/WBEM fallback (internal laptop panels)
    bool m_wmiReady = false;
    IWbemLocator*  m_pWbemLocator  = nullptr;
    IWbemServices* m_pWbemServices = nullptr;
    bool initWmi();
    float getBrightnessWmi();
    void  setBrightnessWmi(float level);

    static float clamp01(float value);

    // Brightness caching
    std::atomic<float> m_cachedBrightness{0.5f};
    std::atomic<ULONGLONG> m_lastBrightnessQueryTime{0};

    // Background thread for brightness
    std::thread m_brightnessThread;
    std::mutex m_mutex;
    std::mutex m_hwMutex;
    std::condition_variable m_cv;
    std::atomic<bool> m_shutdown{false};
    std::atomic<bool> m_hasNewBrightness{false};
    std::atomic<float> m_targetBrightness{0.5f};

    bool m_isWine = false;
};
