#pragma once

#include <windows.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <highlevelmonitorconfigurationapi.h>
#include <physicalmonitorenumerationapi.h>
#include <wbemidl.h>
#include <vector>

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

private:
    WinOSIntegration();
    ~WinOSIntegration();

    IAudioEndpointVolume* getVolumeControl();

    // DDC/CI (external monitors)
    struct MonitorInfo {
        HANDLE hPhysicalMonitor;
    };
    std::vector<MonitorInfo> m_monitors;
    void refreshMonitors();
    void releaseMonitors();

    // WMI/WBEM fallback (internal laptop panels)
    bool m_wmiReady = false;
    IWbemLocator*  m_pWbemLocator  = nullptr;
    IWbemServices* m_pWbemServices = nullptr;
    bool initWmi();
    float getBrightnessWmi();
    void  setBrightnessWmi(float level);
};
