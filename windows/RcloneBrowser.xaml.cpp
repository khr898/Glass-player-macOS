#include "RcloneBrowser.xaml.h"
#include "RcloneBrowser.xaml.g.hpp"
#include "WinOSIntegration.h"

#include <microsoft.ui.xaml.window.h>
#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <regex>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;
using namespace winrt::Microsoft::UI::Xaml::Input;
using namespace winrt::Windows::Web::Http;

namespace winrt::GlassPlayer::implementation
{
    RcloneBrowser::RcloneBrowser()
    {
        InitializeComponent();
        SetupWindow();
    }


    void RcloneBrowser::SetupWindow()
    {
        auto windowNative = this->try_as<IWindowNative>();
        if (windowNative) {
            windowNative->get_WindowHandle(&m_hwnd);
        }

        // Apply custom size (520x600)
        auto appWindow = winrt::Microsoft::UI::Windowing::AppWindow::GetFromWindowId(
            winrt::Microsoft::UI::GetWindowIdFromWindow(m_hwnd));
        appWindow.Resize({ 520, 600 });

        // Apply frosted glass
        WinOSIntegration::instance().applyFrostedGlass(m_hwnd);

        m_httpClient = winrt::Windows::Web::Http::HttpClient();
    }

    void RcloneBrowser::OnConnectClicked(IInspectable const&, RoutedEventArgs const&)
    {
        std::wstring url = UrlField().Text().c_str();
        if (url.empty()) return;

        if (url.find(L"://") == std::wstring::npos) {
            url = L"http://" + url;
        }
        while (!url.empty() && url.back() == L'/') {
            url.pop_back();
        }

        m_baseUrl = url;
        m_currentPath = L"/";
        m_pathHistory.clear();
        m_isConnected = true;

        ConnectBtn().Content(box_value(L"Reconnect"));
        RefreshBtn().IsEnabled(true);

        FetchDirectory();
    }

    void RcloneBrowser::OnBackClicked(IInspectable const&, RoutedEventArgs const&)
    {
        if (m_pathHistory.empty()) return;
        m_currentPath = m_pathHistory.back();
        m_pathHistory.pop_back();
        FetchDirectory();
    }

    void RcloneBrowser::OnUpClicked(IInspectable const&, RoutedEventArgs const&)
    {
        if (m_currentPath == L"/") return;
        m_pathHistory.push_back(m_currentPath);

        // Find last segment
        if (!m_currentPath.empty() && m_currentPath.back() == L'/') {
            m_currentPath.pop_back();
        }
        size_t lastSlash = m_currentPath.find_last_of(L'/');
        if (lastSlash == std::wstring::npos || lastSlash == 0) {
            m_currentPath = L"/";
        } else {
            m_currentPath = m_currentPath.substr(0, lastSlash + 1);
        }
        FetchDirectory();
    }

    void RcloneBrowser::OnRefreshClicked(IInspectable const&, RoutedEventArgs const&)
    {
        if (m_isConnected) {
            FetchDirectory();
        }
    }

    void RcloneBrowser::OnItemDoubleTapped(IInspectable const&, DoubleTappedRoutedEventArgs const&)
    {
        int index = DirectoryList().SelectedIndex();
        if (index < 0 || index >= static_cast<int>(m_entries.size())) return;

        auto entry = m_entries[index];
        if (entry.isDir) {
            m_pathHistory.push_back(m_currentPath);
            m_currentPath += entry.href;
            FetchDirectory();
        } else {
            m_selectedFileUrl = m_baseUrl + m_currentPath + entry.href;
            m_accepted = true;
            Close();
        }
    }

    void RcloneBrowser::OnUrlFieldKeyDown(IInspectable const&, KeyRoutedEventArgs const& args)
    {
        if (args.Key() == winrt::Windows::System::VirtualKey::Enter) {
            OnConnectClicked(nullptr, nullptr);
        }
    }

    // Modern C++/WinRT Coroutine for async HTTP fetch
    void RcloneBrowser::FetchDirectory()
    {
        DirectoryList().Items().Clear();
        DirectoryList().Items().Append(box_value(L"Loading..."));

        BackBtn().IsEnabled(!m_pathHistory.empty());
        UpBtn().IsEnabled(m_currentPath != L"/");

        std::wstring url = m_baseUrl + m_currentPath;
        
        [&]() -> winrt::fire_and_forget {
            try {
                auto uri = winrt::Windows::Foundation::Uri(url);
                auto response = co_await m_httpClient.GetStringAsync(uri);
                
                DispatcherQueue().TryEnqueue([this, html = std::wstring(response)]() {
                    ParseDirectoryListing(html);
                });
            } catch (...) {
                DispatcherQueue().TryEnqueue([this]() {
                    DirectoryList().Items().Clear();
                    DirectoryList().Items().Append(box_value(L"Error connecting to server."));
                });
            }
        }();
    }

    void RcloneBrowser::ParseDirectoryListing(const std::wstring& html)
    {
        DirectoryList().Items().Clear();
        m_entries.clear();

        std::wregex regex(L"<a\\s+href=\"([^\"]+)\"\\s*>([^<]+)</a>\\s*([^<]*)");
        auto begin = std::wsregex_iterator(html.begin(), html.end(), regex);
        auto end = std::wsregex_iterator();

        for (auto it = begin; it != end; ++it) {
            std::wsmatch match = *it;
            std::wstring href = match[1].str();
            std::wstring name = match[2].str();
            std::wstring size = match[3].str();

            if (href == L"../" || href == L".." || href == L"/" || href == L"./") continue;

            bool isDir = !href.empty() && href.back() == L'/';

            ListEntry entry;
            entry.name = name;
            entry.href = href;
            entry.isDir = isDir;
            m_entries.push_back(entry);

            std::wstring displayText;
            if (isDir) {
                displayText = L"[DIR] " + name;
            } else {
                displayText = name + L"  (" + size + L")";
            }
            DirectoryList().Items().Append(box_value(displayText));
        }

        if (m_entries.empty()) {
            DirectoryList().Items().Append(box_value(L"Empty directory"));
        }
    }
}

#include "RcloneBrowser.g.cpp"

