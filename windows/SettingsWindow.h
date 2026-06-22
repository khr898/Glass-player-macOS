#pragma once

#include <windows.h>
#undef GetCurrentTime
#include <string>
#include <vector>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>

class SettingsWindow
{
public:
    SettingsWindow();
    ~SettingsWindow();

    void show();
    void close();

private:
    void setupUi();
    
    // Panel builders
    winrt::Microsoft::UI::Xaml::UIElement buildGeneralSection();
    winrt::Microsoft::UI::Xaml::UIElement buildVideoSection();
    winrt::Microsoft::UI::Xaml::UIElement buildAudioSection();
    winrt::Microsoft::UI::Xaml::UIElement buildSubtitlesSection();
    winrt::Microsoft::UI::Xaml::UIElement buildNetworkSection();
    winrt::Microsoft::UI::Xaml::UIElement buildScalingSection();
    winrt::Microsoft::UI::Xaml::UIElement buildColorSection();
    winrt::Microsoft::UI::Xaml::UIElement buildAnime4KSection();
    winrt::Microsoft::UI::Xaml::UIElement buildShortcutsSection();

    // Helpers
    winrt::Microsoft::UI::Xaml::Controls::ToggleSwitch addToggle(winrt::Microsoft::UI::Xaml::Controls::StackPanel& panel, const std::wstring& title, const std::wstring& key, bool defaultValue);
    winrt::Microsoft::UI::Xaml::Controls::ComboBox addCombo(winrt::Microsoft::UI::Xaml::Controls::StackPanel& panel, const std::wstring& title, const std::wstring& key, const std::vector<std::wstring>& options, const std::wstring& defaultValue);

    winrt::Microsoft::UI::Xaml::Window m_window{ nullptr };
    HWND m_hwnd{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::NavigationView m_navView{ nullptr };
};
