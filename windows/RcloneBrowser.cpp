#include "RcloneBrowser.h"
#include <dwmapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.Web.Http.h>
#include <regex>
#include <stdexcept>

struct __declspec(uuid("EECDB3DB-E257-4A86-844C-5B09F6F35B04")) IWindowNative : IUnknown
{
    virtual HRESULT __stdcall get_WindowHandle(HWND* hWnd) = 0;
};

RcloneBrowser::RcloneBrowser()
{
    m_window = winrt::Microsoft::UI::Xaml::Window();
    m_window.as<IWindowNative>()->get_WindowHandle(&m_hwnd);

    m_window.Title(L"Cloud Streams Browser");
    
    auto appWindow = m_window.AppWindow();
    appWindow.Resize(winrt::Windows::Graphics::SizeInt32{ 700, 480 });

    // Enable Mica Backdrop
    winrt::Microsoft::UI::Xaml::Media::MicaBackdrop mica;
    m_window.SystemBackdrop(mica);

    // Dark Mode titlebar style
    BOOL darkMode = TRUE;
    DwmSetWindowAttribute(m_hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &darkMode, sizeof(darkMode));

    m_dispatcherQueue = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread();

    setupUi();
}

RcloneBrowser::~RcloneBrowser()
{
}

void RcloneBrowser::setupUi()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;
    using namespace winrt::Microsoft::UI::Xaml::Media;

    Grid rootGrid = Grid();
    rootGrid.Padding(Thickness{ 20 });

    RowDefinition r1, r2, r3;
    r1.Height(GridLength{ 1, GridUnitType::Auto });
    r2.Height(GridLength{ 1, GridUnitType::Auto });
    r3.Height(GridLength{ 1, GridUnitType::Star });
    rootGrid.RowDefinitions().Append(r1);
    rootGrid.RowDefinitions().Append(r2);
    rootGrid.RowDefinitions().Append(r3);

    // Connection URL Row
    Grid connGrid = Grid();
    connGrid.Margin(Thickness{ 0, 0, 0, 10 });
    ColumnDefinition c1, c2;
    c1.Width(GridLength{ 1, GridUnitType::Star });
    c2.Width(GridLength{ 1, GridUnitType::Auto });
    connGrid.ColumnDefinitions().Append(c1);
    connGrid.ColumnDefinitions().Append(c2);
    rootGrid.SetRow(connGrid, 0);

    m_urlField = TextBox();
    m_urlField.PlaceholderText(L"http://localhost:8080");
    m_urlField.Text(L"http://localhost:8080");
    m_urlField.VerticalAlignment(VerticalAlignment::Center);
    connGrid.SetColumn(m_urlField, 0);
    connGrid.Children().Append(m_urlField);

    m_connectBtn = Button();
    m_connectBtn.Content(winrt::box_value(L"Connect"));
    m_connectBtn.Margin(Thickness{ 10, 0, 0, 0 });
    m_connectBtn.Background(SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(255, 0, 120, 215)));
    m_connectBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    m_connectBtn.Click([this](auto const&, auto const&) { onConnectClicked(); });
    connGrid.SetColumn(m_connectBtn, 1);
    connGrid.Children().Append(m_connectBtn);

    rootGrid.Children().Append(connGrid);

    // Navigation buttons row
    StackPanel navPanel;
    navPanel.Orientation(Orientation::Horizontal);
    navPanel.Margin(Thickness{ 0, 0, 0, 10 });
    rootGrid.SetRow(navPanel, 1);

    m_backBtn = Button();
    m_backBtn.Content(winrt::box_value(L"←"));
    m_backBtn.Width(36);
    m_backBtn.IsEnabled(false);
    m_backBtn.Margin(Thickness{ 0, 0, 5, 0 });
    m_backBtn.Click([this](auto const&, auto const&) { onBackClicked(); });
    navPanel.Children().Append(m_backBtn);

    m_upBtn = Button();
    m_upBtn.Content(winrt::box_value(L"↑"));
    m_upBtn.Width(36);
    m_upBtn.IsEnabled(false);
    m_upBtn.Margin(Thickness{ 0, 0, 5, 0 });
    m_upBtn.Click([this](auto const&, auto const&) { onUpClicked(); });
    navPanel.Children().Append(m_upBtn);

    m_refreshBtn = Button();
    m_refreshBtn.Content(winrt::box_value(L"⟳"));
    m_refreshBtn.Width(36);
    m_refreshBtn.IsEnabled(false);
    m_refreshBtn.Click([this](auto const&, auto const&) { onRefreshClicked(); });
    navPanel.Children().Append(m_refreshBtn);

    rootGrid.Children().Append(navPanel);

    // ListView
    m_listView = ListView();
    m_listView.Background(SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(15, 255, 255, 255)));
    m_listView.BorderBrush(SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(40, 255, 255, 255)));
    m_listView.BorderThickness(Thickness{ 1 });
    m_listView.CornerRadius(CornerRadius{ 4 });
    
    // Connect double click handler
    m_listView.DoubleTapped([this](auto const&, auto const&) {
        onItemDoubleClicked();
    });

    rootGrid.SetRow(m_listView, 2);
    rootGrid.Children().Append(m_listView);

    m_window.Content(rootGrid);
}

void RcloneBrowser::onConnectClicked()
{
    std::wstring url = m_urlField.Text().c_str();
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

    m_connectBtn.Content(winrt::box_value(L"Reconnect"));
    m_refreshBtn.IsEnabled(true);

    fetchDirectory();
}

void RcloneBrowser::onBackClicked()
{
    if (m_pathHistory.empty()) return;
    m_currentPath = m_pathHistory.back();
    m_pathHistory.pop_back();
    fetchDirectory();
}

void RcloneBrowser::onUpClicked()
{
    if (m_currentPath == L"/") return;
    m_pathHistory.push_back(m_currentPath);

    // Navigate up one level in HTTP folder structure
    std::wstring path = m_currentPath;
    if (!path.empty() && path.back() == L'/') {
        path.pop_back();
    }
    
    size_t lastSlash = path.find_last_of(L'/');
    if (lastSlash == std::wstring::npos || lastSlash == 0) {
        m_currentPath = L"/";
    } else {
        m_currentPath = path.substr(0, lastSlash + 1);
    }
    fetchDirectory();
}

void RcloneBrowser::onRefreshClicked()
{
    if (!m_isConnected) return;
    fetchDirectory();
}

void RcloneBrowser::onItemDoubleClicked()
{
    int index = m_listView.SelectedIndex();
    if (index < 0 || index >= static_cast<int>(m_currentItems.size())) return;

    auto const& item = m_currentItems[index];
    if (item.isDir) {
        m_pathHistory.push_back(m_currentPath);
        m_currentPath = m_currentPath + item.href;
        fetchDirectory();
    } else {
        std::wstring fullUrl = m_baseUrl + m_currentPath + item.href;
        if (m_fileSelectedCallback) {
            m_fileSelectedCallback(fullUrl);
        }
    }
}

void RcloneBrowser::fetchDirectory()
{
    m_backBtn.IsEnabled(!m_pathHistory.empty());
    m_upBtn.IsEnabled(m_currentPath != L"/");

    m_listView.Items().Clear();
    m_listView.Items().Append(winrt::box_value(L"Loading..."));

    std::wstring urlString = m_baseUrl + m_currentPath;

    // Use winrt::Windows::Web::Http::HttpClient
    winrt::Windows::Web::Http::HttpClient httpClient;
    winrt::Windows::Foundation::Uri uri(urlString);

    httpClient.GetStringAsync(uri).Completed([this](auto const& op, auto const& status) {
        if (status == winrt::Windows::Foundation::AsyncStatus::Completed) {
            auto html = op.GetResults();
            m_dispatcherQueue.TryEnqueue([this, html = std::wstring(html)]() {
                parseDirectoryListing(html);
            });
        } else {
            m_dispatcherQueue.TryEnqueue([this]() {
                m_listView.Items().Clear();
                m_listView.Items().Append(winrt::box_value(L"Error connecting to server."));
            });
        }
    });
}

void RcloneBrowser::parseDirectoryListing(const std::wstring& html)
{
    m_listView.Items().Clear();
    m_currentItems.clear();

    // Standard regex to parse HTML anchors: <a href="link">name</a> size
    std::wregex regex(L"<a\\s+href=\"([^\"]+)\"\\s*>([^<]+)</a>\\s*([^<]*)", std::regex_constants::icase);
    auto it = std::wsregex_iterator(html.begin(), html.end(), regex);
    auto end = std::wsregex_iterator();

    for (; it != end; ++it) {
        std::wsmatch match = *it;
        std::wstring href = match[1].str();
        std::wstring name = match[2].str();
        std::wstring size = match[3].str();

        // Trim name and size
        name.erase(0, name.find_first_not_of(L" \t\r\n"));
        name.erase(name.find_last_not_of(L" \t\r\n") + 1);
        size.erase(0, size.find_first_not_of(L" \t\r\n"));
        size.erase(size.find_last_not_of(L" \t\r\n") + 1);

        if (href == L"../" || href == L".." || href == L"/" || href == L"./") {
            continue;
        }

        bool isDir = (!href.empty() && href.back() == L'/');
        
        RcloneItem item;
        item.name = name;
        item.href = href;
        item.isDir = isDir;

        if (isDir) {
            item.displayString = L"📁 " + name;
        } else {
            item.displayString = L"📄 " + name + (size.empty() ? L"" : L"   (" + size + L")");
        }

        m_currentItems.push_back(item);
        m_listView.Items().Append(winrt::box_value(item.displayString));
    }

    if (m_currentItems.empty()) {
        m_listView.Items().Append(winrt::box_value(L"Empty directory"));
    }
}

void RcloneBrowser::show()
{
    m_window.Activate();
}

void RcloneBrowser::close()
{
    m_window.Close();
}
