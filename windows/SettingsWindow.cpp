#include "SettingsWindow.h"
#include <dwmapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>

struct __declspec(uuid("EECDB3DB-E257-4A86-844C-5B09F6F35B04")) IWindowNative : IUnknown
{
    virtual HRESULT __stdcall get_WindowHandle(HWND* hWnd) = 0;
};

// Helper struct for Registry-based configuration
struct RegistryConfig {
    static std::wstring getString(const std::wstring& key, const std::wstring& defaultValue) {
        HKEY hKey;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Glass Player\\Glass Player", 0, KEY_READ, &hKey) == ERROR_SUCCESS) {
            wchar_t buf[256];
            DWORD size = sizeof(buf);
            if (RegQueryValueExW(hKey, key.c_str(), nullptr, nullptr, (LPBYTE)buf, &size) == ERROR_SUCCESS) {
                RegCloseKey(hKey);
                return buf;
            }
            RegCloseKey(hKey);
        }
        return defaultValue;
    }

    static void setString(const std::wstring& key, const std::wstring& value) {
        HKEY hKey;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Glass Player\\Glass Player", 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr) == ERROR_SUCCESS) {
            RegSetValueExW(hKey, key.c_str(), 0, REG_SZ, (const BYTE*)value.c_str(), (DWORD)((value.length() + 1) * sizeof(wchar_t)));
            RegCloseKey(hKey);
        }
    }

    static bool getBool(const std::wstring& key, bool defaultValue) {
        std::wstring res = getString(key, defaultValue ? L"true" : L"false");
        return res == L"true";
    }

    static void setBool(const std::wstring& key, bool value) {
        setString(key, value ? L"true" : L"false");
    }
};

SettingsWindow::SettingsWindow()
{
    m_window = winrt::Microsoft::UI::Xaml::Window();
    m_window.as<IWindowNative>()->get_WindowHandle(&m_hwnd);

    m_window.Title(L"Settings");
    
    auto appWindow = m_window.AppWindow();
    appWindow.Resize(winrt::Windows::Graphics::SizeInt32{ 750, 500 });

    // Enable Mica Backdrop
    winrt::Microsoft::UI::Xaml::Media::MicaBackdrop mica;
    m_window.SystemBackdrop(mica);

    // Immersive Dark Mode titlebar
    BOOL darkMode = TRUE;
    DwmSetWindowAttribute(m_hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &darkMode, sizeof(darkMode));

    setupUi();
}

SettingsWindow::~SettingsWindow()
{
}

void SettingsWindow::setupUi()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;
    using namespace winrt::Microsoft::UI::Xaml::Media;

    m_navView = NavigationView();
    m_navView.PaneDisplayMode(NavigationViewPaneDisplayMode::Left);
    m_navView.IsSettingsVisible(false);
    m_navView.IsBackButtonVisible(NavigationViewBackButtonVisible::Collapsed);

    // Setup Sidebar Items
    std::vector<std::wstring> sections = {
        L"General", L"Video", L"Audio", L"Subtitles", L"Network", L"Scaling", L"Color", L"Anime4K", L"Shortcuts"
    };

    for (auto const& sec : sections) {
        NavigationViewItem item;
        item.Content(winrt::box_value(sec));
        item.Tag(winrt::box_value(sec));
        m_navView.MenuItems().Append(item);
    }

    // Handle section changes
    m_navView.SelectionChanged([this](auto const& sender, NavigationViewSelectionChangedEventArgs const& args) {
        auto item = args.SelectedItem().as<NavigationViewItem>();
        if (item) {
            std::wstring tag = winrt::unbox_value<winrt::hstring>(item.Tag()).c_str();
            
            if (tag == L"General") m_navView.Content(buildGeneralSection());
            else if (tag == L"Video") m_navView.Content(buildVideoSection());
            else if (tag == L"Audio") m_navView.Content(buildAudioSection());
            else if (tag == L"Subtitles") m_navView.Content(buildSubtitlesSection());
            else if (tag == L"Network") m_navView.Content(buildNetworkSection());
            else if (tag == L"Scaling") m_navView.Content(buildScalingSection());
            else if (tag == L"Color") m_navView.Content(buildColorSection());
            else if (tag == L"Anime4K") m_navView.Content(buildAnime4KSection());
            else if (tag == L"Shortcuts") m_navView.Content(buildShortcutsSection());
        }
    });

    // Default selection
    m_navView.SelectedItem(m_navView.MenuItems().GetAt(0));

    m_window.Content(m_navView);
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildGeneralSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(15);

    TextBlock header = TextBlock();
    header.Text(L"General Settings");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    addToggle(panel, L"Remember Position", L"rememberPosition", true);
    addCombo(panel, L"Window Resize Behavior", L"windowResize", { L"Keep Aspect", L"Resize Freely" }, L"Keep Aspect");
    addCombo(panel, L"Cursor Auto-hide (ms)", L"cursorAutohide", { L"1000", L"2000", L"3000", L"Never" }, L"2000");

    return panel;
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildVideoSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(15);

    TextBlock header = TextBlock();
    header.Text(L"Video Settings");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    addCombo(panel, L"Hardware Decoding", L"hwdec", { L"d3d11va", L"nvdec", L"qsv", L"none" }, L"d3d11va");
    addCombo(panel, L"Hardware Decode Codecs", L"hwdecCodecs", { L"all", L"h264,hevc", L"hevc,vp9" }, L"all");
    addToggle(panel, L"Deband Filter", L"deband", true);

    return panel;
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildAudioSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(15);

    TextBlock header = TextBlock();
    header.Text(L"Audio Settings");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    addCombo(panel, L"Audio Output API", L"audioOutput", { L"wasapi", L"openal", L"sdl" }, L"wasapi");
    addCombo(panel, L"Maximum Volume Limit", L"volumeMax", { L"100", L"130", L"150", L"200" }, L"200");
    addToggle(panel, L"Enable Audio Pass-through (Bitstream)", L"audioPassThrough", false);

    return panel;
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildSubtitlesSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(15);

    TextBlock header = TextBlock();
    header.Text(L"Subtitles Settings");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    addCombo(panel, L"Subtitle Font Size", L"subFontSize", { L"40", L"48", L"55", L"64" }, L"48");
    addCombo(panel, L"Font Style", L"subFont", { L"Segoe UI", L"Arial", L"Trebuchet MS" }, L"Segoe UI");
    addCombo(panel, L"Border Outline Size", L"subBorderSize", { L"1", L"2", L"3", L"4" }, L"2");

    return panel;
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildNetworkSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(15);

    TextBlock header = TextBlock();
    header.Text(L"Network Cache Settings");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    addCombo(panel, L"Demuxer Cache Size (MB)", L"cacheSizeMB", { L"50", L"150", L"500", L"1024" }, L"150");
    addCombo(panel, L"Network Timeout (secs)", L"networkTimeout", { L"15", L"30", L"60" }, L"30");

    return panel;
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildScalingSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(15);

    TextBlock header = TextBlock();
    header.Text(L"Scaling & Rendering Filters");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    addCombo(panel, L"Upscale Scaling Filter", L"scaleFilter", { L"spline36", L"lanczos", L"ewa_lanczossharp", L"bilinear" }, L"spline36");
    addCombo(panel, L"Downscale Scaling Filter", L"dscaleFilter", { L"mitchell", L"spline36", L"bilinear" }, L"mitchell");

    return panel;
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildColorSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(15);

    TextBlock header = TextBlock();
    header.Text(L"Color & HDR Tone Mapping");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    addCombo(panel, L"Tone Mapping Curve", L"toneMapping", { L"bt.2390", L"hable", L"reinhard", L"mobius" }, L"bt.2390");
    addCombo(panel, L"Tone Mapping Mode", L"toneMappingMode", { L"auto", L"clip", L"linear" }, L"auto");

    return panel;
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildAnime4KSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(15);

    TextBlock header = TextBlock();
    header.Text(L"Anime4K Real-time Upscaling");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    addCombo(panel, L"Default Shader Preset", L"defaultShaderPreset", { L"ModeA", L"ModeB", L"ModeC", L"ModeAA", L"ModeBB", L"ModeCA", L"None" }, L"None");

    return panel;
}

winrt::Microsoft::UI::Xaml::UIElement SettingsWindow::buildShortcutsSection()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;
    using namespace winrt::Microsoft::UI::Xaml::Media;

    StackPanel panel;
    panel.Padding(Thickness{ 20 });
    panel.Spacing(10);

    TextBlock header = TextBlock();
    header.Text(L"Keyboard Shortcuts");
    header.FontSize(20);
    header.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    panel.Children().Append(header);

    // List shortcuts
    struct HotkeyInfo {
        std::wstring action;
        std::wstring key;
    };
    std::vector<HotkeyInfo> hotkeys = {
        { L"Play / Pause", L"Space / K" },
        { L"Toggle Fullscreen", L"F" },
        { L"Exit Fullscreen", L"Escape" },
        { L"Seek Backward 5s", L"Left Arrow" },
        { L"Seek Forward 5s", L"Right Arrow" },
        { L"Volume Up", L"Up Arrow" },
        { L"Volume Down", L"Down Arrow" },
        { L"Mute / Unmute", L"M" }
    };

    for (auto const& hk : hotkeys) {
        Grid rowGrid = Grid();
        ColumnDefinition c1, c2;
        c1.Width(GridLength{ 1, GridUnitType::Star });
        c2.Width(GridLength{ 1, GridUnitType::Auto });
        rowGrid.ColumnDefinitions().Append(c1);
        rowGrid.ColumnDefinitions().Append(c2);

        TextBlock desc = TextBlock();
        desc.Text(hk.action);
        desc.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::LightGray()));
        desc.VerticalAlignment(VerticalAlignment::Center);
        rowGrid.SetColumn(desc, 0);
        rowGrid.Children().Append(desc);

        Border keyBorder = Border();
        keyBorder.Background(SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(40, 255, 255, 255)));
        keyBorder.CornerRadius(CornerRadius{ 4 });
        keyBorder.Padding(Thickness{ 8, 4, 8, 4 });
        rowGrid.SetColumn(keyBorder, 1);

        TextBlock keyText = TextBlock();
        keyText.Text(hk.key);
        keyText.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
        keyText.FontSize(11);
        keyText.FontWeight(winrt::Windows::UI::Text::FontWeights::Bold());
        keyBorder.Child(keyText);

        rowGrid.Children().Append(keyBorder);
        panel.Children().Append(rowGrid);
    }

    return panel;
}

winrt::Microsoft::UI::Xaml::Controls::ToggleSwitch SettingsWindow::addToggle(
    winrt::Microsoft::UI::Xaml::Controls::StackPanel& panel,
    const std::wstring& title, const std::wstring& key, bool defaultValue)
{
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    ToggleSwitch ts = ToggleSwitch();
    ts.Header(winrt::box_value(title));
    
    bool currentVal = RegistryConfig::getBool(key, defaultValue);
    ts.IsOn(currentVal);

    ts.Toggled([key](auto const& sender, auto const&) {
        auto toggle = sender.as<ToggleSwitch>();
        RegistryConfig::setBool(key, toggle.IsOn());
    });

    panel.Children().Append(ts);
    return ts;
}

winrt::Microsoft::UI::Xaml::Controls::ComboBox SettingsWindow::addCombo(
    winrt::Microsoft::UI::Xaml::Controls::StackPanel& panel,
    const std::wstring& title, const std::wstring& key,
    const std::vector<std::wstring>& options, const std::wstring& defaultValue)
{
    using namespace winrt::Microsoft::UI::Xaml::Controls;

    ComboBox cb = ComboBox();
    cb.Header(winrt::box_value(title));
    cb.Width(200);

    std::wstring currentVal = RegistryConfig::getString(key, defaultValue);
    int selectedIndex = 0;

    for (size_t i = 0; i < options.size(); ++i) {
        cb.Items().Append(winrt::box_value(options[i]));
        if (options[i] == currentVal) {
            selectedIndex = static_cast<int>(i);
        }
    }
    cb.SelectedIndex(selectedIndex);

    cb.SelectionChanged([key, options](auto const& sender, auto const&) {
        auto combo = sender.as<ComboBox>();
        int idx = combo.SelectedIndex();
        if (idx >= 0 && idx < static_cast<int>(options.size())) {
            RegistryConfig::setString(key, options[idx]);
        }
    });

    panel.Children().Append(cb);
    return cb;
}

void SettingsWindow::show()
{
    m_window.Activate();
}

void SettingsWindow::close()
{
    m_window.Close();
}
