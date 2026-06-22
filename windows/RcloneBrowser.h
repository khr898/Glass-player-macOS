#pragma once

#include <windows.h>
#undef GetCurrentTime
#include <string>
#include <vector>
#include <functional>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Dispatching.h>

class RcloneBrowser
{
public:
    RcloneBrowser();
    ~RcloneBrowser();

    void show();
    void close();

    void fileSelected(std::function<void(const std::wstring&)> cb) { m_fileSelectedCallback = cb; }

private:
    void setupUi();
    void fetchDirectory();
    void parseDirectoryListing(const std::wstring& html);
    void onConnectClicked();
    void onBackClicked();
    void onUpClicked();
    void onRefreshClicked();
    void onItemDoubleClicked();

    winrt::Microsoft::UI::Xaml::Window m_window{ nullptr };
    HWND m_hwnd{ nullptr };
    winrt::Microsoft::UI::Dispatching::DispatcherQueue m_dispatcherQueue{ nullptr };

    std::function<void(const std::wstring&)> m_fileSelectedCallback;

    // Controls
    winrt::Microsoft::UI::Xaml::Controls::TextBox m_urlField{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Button m_connectBtn{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Button m_backBtn{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Button m_upBtn{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::Button m_refreshBtn{ nullptr };
    winrt::Microsoft::UI::Xaml::Controls::ListView m_listView{ nullptr };

    // Navigation state
    std::wstring m_baseUrl;
    std::wstring m_currentPath;
    std::vector<std::wstring> m_pathHistory;
    bool m_isConnected{ false };

    struct RcloneItem {
        std::wstring name;
        std::wstring href;
        bool isDir;
        std::wstring displayString;
    };
    std::vector<RcloneItem> m_currentItems;
};
