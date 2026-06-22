#pragma once

#include <windows.h>
#undef GetCurrentTime
#include <string>
#include <functional>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Dispatching.h>

class WelcomeWindow
{
public:
    WelcomeWindow();
    ~WelcomeWindow();

    void show();
    void close();

    void fileOpened(std::function<void(const std::wstring&)> cb) { m_fileOpenedCallback = cb; }
    void openRcloneBrowser(std::function<void()> cb) { m_openRcloneBrowserCallback = cb; }

private:
    void setupUi();

    winrt::Microsoft::UI::Xaml::Window m_window{ nullptr };
    HWND m_hwnd{ nullptr };
    winrt::Microsoft::UI::Dispatching::DispatcherQueue m_dispatcherQueue{ nullptr };

    std::function<void(const std::wstring&)> m_fileOpenedCallback;
    std::function<void()> m_openRcloneBrowserCallback;
};
