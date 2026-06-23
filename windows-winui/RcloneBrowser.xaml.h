#pragma once

#include <unknwn.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <windows.h>
#undef GetCurrentTime

#include "RcloneBrowser.g.h"
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Windows.Web.Http.h>
#include <string>
#include <vector>

namespace winrt::GlassPlayer::implementation
{
    struct RcloneBrowser : RcloneBrowserT<RcloneBrowser>
    {
        RcloneBrowser();

        void OnConnectClicked(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& args);
        void OnBackClicked(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& args);
        void OnUpClicked(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& args);
        void OnRefreshClicked(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& args);
        void OnItemDoubleTapped(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::Input::DoubleTappedRoutedEventArgs const& args);
        void OnUrlFieldKeyDown(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::Input::KeyRoutedEventArgs const& args);

        std::wstring SelectedFileUrl() const { return m_selectedFileUrl; }
        bool Accepted() const { return m_accepted; }

    private:
        void SetupWindow();
        void FetchDirectory();
        void ParseDirectoryListing(const std::wstring& html);

        struct ListEntry {
            std::wstring name;
            std::wstring href;
            bool isDir;
        };

        HWND m_hwnd{ nullptr };
        winrt::Windows::Web::Http::HttpClient m_httpClient{ nullptr };
        std::wstring m_baseUrl;
        std::wstring m_currentPath;
        std::vector<std::wstring> m_pathHistory;
        std::vector<ListEntry> m_entries;
        bool m_isConnected{ false };
        std::wstring m_selectedFileUrl;
        bool m_accepted{ false };
    };
}

namespace winrt::GlassPlayer::factory_implementation
{
    struct RcloneBrowser : RcloneBrowserT<RcloneBrowser, implementation::RcloneBrowser>
    {
    };
}
