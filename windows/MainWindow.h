#pragma once

#include <windows.h>
#undef GetCurrentTime
#include <string>
#include <memory>
#include <functional>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Dispatching.h>

#include "MpvManager.h"

class MainWindow : public std::enable_shared_from_this<MainWindow>
{
public:
    MainWindow();
    ~MainWindow();

    void openFile(const std::wstring& filePath);
    void setAnime4kPreset(const std::wstring& preset);
    void suppressWelcome();
    bool shouldShowWelcome() const;
    void openRcloneBrowserDirectly();
    void show();
    void executeCommand(const std::wstring& command);

private:
    static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);
    LRESULT handleMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

    void registerWindowClass();
    void createVideoWindow();
    void createHudWindow();
    void syncHudPosition();

    // UI creation
    void setupHudLayout();
    void updateHudData(double pos);
    void updateDuration(double dur);
    void onPlayPauseClicked();
    void onSliderMoved(double val);
    void onVolumeChanged(double val);
    void onMuteClicked();
    void onSettingsClicked();
    void onRcloneClicked();
    void toggleFullscreen();
    void showHudElements();
    void hideHudElements();
    void updateVolumeIcon();
    std::wstring formatTime(double seconds);

    // HWNDs
    HWND m_hwndVideo{ nullptr };
    HWND m_hwndChildVideo{ nullptr };
    HWND m_hwndHud{ nullptr };

    // WinUI 3 HUD Window
    winrt::Microsoft::UI::Xaml::Window m_hudWindow{ nullptr };

    // Player manager
    std::unique_ptr<MpvManager> m_mpv;

    // Window state
    bool m_welcomeSuppressed{ false };
    bool m_isFullscreen{ false };
    WINDOWPLACEMENT m_wpPrev{ sizeof(WINDOWPLACEMENT) };

    // Playback state
    double m_duration{ 0.0 };
    double m_position{ 0.0 };
    bool m_isPlaying{ false };
    bool m_isMuted{ false };
    int m_volume{ 100 };
    std::wstring m_currentFilePath;

    winrt::Microsoft::UI::Dispatching::DispatcherQueue m_dispatcherQueue{ nullptr };

    // HUD Auto-hide
    winrt::Microsoft::UI::Dispatching::DispatcherQueueTimer m_hudTimer{ nullptr };
    bool m_hudVisible{ true };

    // WinUI Controls
    winrt::Microsoft::UI::Xaml::Controls::Grid m_rootGrid{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Grid m_topBar{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Grid m_bottomBar{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Slider m_seekSlider{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Slider m_volumeSlider{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Button m_playPauseBtn{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Button m_muteBtn{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::TextBlock m_titleLabel{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::TextBlock m_timeLabel{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::TextBlock m_remainingTimeLabel{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Border m_resolutionBadge{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::TextBlock m_resolutionText{ nullptr };
};
