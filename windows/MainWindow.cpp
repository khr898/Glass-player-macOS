#include "MainWindow.h"
#include "WelcomeWindow.h"
#include "SettingsWindow.h"
#include "RcloneBrowser.h"

#include <stdexcept>
#include <locale>
#include <codecvt>
#include <fstream>
#include <dwmapi.h>
#include <shlwapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>
#include <winrt/Microsoft.UI.Xaml.Media.Animation.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <shlobj.h>
#include <shobjidl.h>

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "Shlwapi.lib")

struct __declspec(uuid("EECDB3DB-E257-4A86-844C-5B09F6F35B04")) IWindowNative : IUnknown
{
    virtual HRESULT __stdcall get_WindowHandle(HWND* hWnd) = 0;
};

inline void LogMessage(const std::wstring& msg)
{
    wchar_t tempPath[MAX_PATH];
    if (GetTempPathW(MAX_PATH, tempPath)) {
        std::wstring logPath = std::wstring(tempPath) + L"glass_player_debug.log";
        std::wofstream logFile(logPath, std::ios::app);
        if (logFile.is_open()) {
            logFile << msg << std::endl;
        }
    }
}

MainWindow::MainWindow()
{
    LogMessage(L"MainWindow::MainWindow - Started");
    m_dispatcherQueue = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread();
    
    LogMessage(L"MainWindow::MainWindow - Creating MpvManager");
    m_mpv = std::make_unique<MpvManager>();
    
    LogMessage(L"MainWindow::MainWindow - Registering window class");
    registerWindowClass();
    
    LogMessage(L"MainWindow::MainWindow - Creating video window");
    createVideoWindow();
    
    LogMessage(L"MainWindow::MainWindow - Creating HUD window");
    createHudWindow();
    
    LogMessage(L"MainWindow::MainWindow - Syncing HUD position");
    // Position HUD exactly on top of video window
    syncHudPosition();
    LogMessage(L"MainWindow::MainWindow - Completed");
}

MainWindow::~MainWindow()
{
    if (m_mpv) {
        m_mpv->terminate();
    }
    if (m_hwndVideo) {
        DestroyWindow(m_hwndVideo);
    }
    if (m_hwndHud) {
        m_hudWindow.Close();
    }
}

void MainWindow::registerWindowClass()
{
    WNDCLASSEXW wcx = { 0 };
    wcx.cbSize = sizeof(WNDCLASSEXW);
    wcx.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    wcx.lpfnWndProc = WndProc;
    wcx.hInstance = GetModuleHandle(nullptr);
    wcx.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wcx.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
    wcx.lpszClassName = L"GlassPlayerVideoWindowClass";

    RegisterClassExW(&wcx);
}

void MainWindow::createVideoWindow()
{
    m_hwndVideo = CreateWindowExW(
        0, L"GlassPlayerVideoWindowClass", L"Glass Player",
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        CW_USEDEFAULT, CW_USEDEFAULT, 1280, 720,
        nullptr, nullptr, GetModuleHandle(nullptr), this
    );

    if (!m_hwndVideo) {
        throw std::runtime_error("Failed to create video window");
    }

    // Set immersive dark mode title bar
    BOOL darkMode = TRUE;
    DwmSetWindowAttribute(m_hwndVideo, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &darkMode, sizeof(darkMode));

    // Create child window for mpv rendering
    m_hwndChildVideo = CreateWindowExW(
        0, L"Static", nullptr,
        WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
        0, 0, 1280, 720,
        m_hwndVideo, nullptr, GetModuleHandle(nullptr), nullptr
    );

    m_mpv->initialize(m_hwndChildVideo);

    // Setup callbacks
    m_mpv->setOnPositionChanged([this](double pos) {
        updateHudData(pos);
    });
    m_mpv->setOnDurationChanged([this](double dur) {
        updateDuration(dur);
    });
    m_mpv->setOnPauseChanged([this](bool paused) {
        m_isPlaying = !paused;
        m_playPauseBtn.Content(winrt::box_value(m_isPlaying ? L"⏸" : L"▶"));
    });
    m_mpv->setOnFileLoaded([this]() {
        // Retrieve resolution info
        int w = m_mpv->getPropertyInt("video-params/w");
        int h = m_mpv->getPropertyInt("video-params/h");
        if (w > 0 && h > 0) {
            std::wstring resStr = std::to_wstring(w) + L"x" + std::to_wstring(h);
            m_resolutionText.Text(resStr);
            m_resolutionBadge.Visibility(winrt::Microsoft::UI::Xaml::Visibility::Visible);
        } else {
            m_resolutionBadge.Visibility(winrt::Microsoft::UI::Xaml::Visibility::Collapsed);
        }
    });
}

void MainWindow::createHudWindow()
{
    m_hudWindow = winrt::Microsoft::UI::Xaml::Window();
    
    // Obtain HWND
    m_hudWindow.as<IWindowNative>()->get_WindowHandle(&m_hwndHud);

    // Remove titlebar and borders
    auto appWindow = m_hudWindow.AppWindow();
    auto presenter = appWindow.Presenter().as<winrt::Microsoft::UI::Windowing::OverlappedPresenter>();
    presenter.SetBorderAndTitleBar(false, false);

    // Style the window as a transparent click-through overlay using DWM
    LONG_PTR exStyle = GetWindowLongPtr(m_hwndHud, GWL_EXSTYLE);
    SetWindowLongPtr(m_hwndHud, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE | WS_EX_LAYERED);
    SetWindowLongPtr(m_hwndHud, GWLP_HWNDPARENT, (LONG_PTR)m_hwndVideo); // owned window

    // Apply transparent background frame extension
    MARGINS margins = { -1, -1, -1, -1 };
    DwmExtendFrameIntoClientArea(m_hwndHud, &margins);

    setupHudLayout();
}

void MainWindow::syncHudPosition()
{
    if (!m_hwndVideo || !m_hwndHud) return;

    RECT rect;
    GetClientRect(m_hwndVideo, &rect);

    POINT pt = { rect.left, rect.top };
    ClientToScreen(m_hwndVideo, &pt);

    // Set HUD window position and size to match the video window client area
    SetWindowPos(m_hwndHud, nullptr, pt.x, pt.y, rect.right - rect.left, rect.bottom - rect.top, SWP_NOZORDER | SWP_NOACTIVATE);
}

void MainWindow::setupHudLayout()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;
    using namespace winrt::Microsoft::UI::Xaml::Controls::Primitives;
    using namespace winrt::Microsoft::UI::Xaml::Media;

    m_rootGrid = Grid();
    
    // We do NOT set the background of rootGrid, leaving it as null so clicks pass through!
    
    // Setup Top Bar
    m_topBar = Grid();
    m_topBar.Height(50);
    m_topBar.VerticalAlignment(VerticalAlignment::Top);
    m_topBar.Padding(Thickness{ 15, 5, 15, 5 });
    
    // Subtle dark gradient background for top bar
    LinearGradientBrush topBg;
    GradientStop stop1, stop2;
    stop1.Color(winrt::Windows::UI::ColorHelper::FromArgb(200, 20, 20, 20));
    stop1.Offset(0.0);
    stop2.Color(winrt::Windows::UI::ColorHelper::FromArgb(0, 20, 20, 20));
    stop2.Offset(1.0);
    topBg.GradientStops().Append(stop1);
    topBg.GradientStops().Append(stop2);
    m_topBar.Background(topBg);

    ColumnDefinition col1, col2, col3;
    col1.Width(GridLength{ 1, GridUnitType::Star });
    col2.Width(GridLength{ 1, GridUnitType::Auto });
    col3.Width(GridLength{ 1, GridUnitType::Star });
    m_topBar.ColumnDefinitions().Append(col1);
    m_topBar.ColumnDefinitions().Append(col2);
    m_topBar.ColumnDefinitions().Append(col3);

    m_titleLabel = TextBlock();
    m_titleLabel.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::LightGray()));
    m_titleLabel.VerticalAlignment(VerticalAlignment::Center);
    m_titleLabel.FontSize(13);
    m_titleLabel.Text(L"Glass Player");
    m_topBar.SetColumn(m_titleLabel, 0);
    m_topBar.Children().Append(m_titleLabel);

    // Resolution badge Border
    m_resolutionBadge = Border();
    m_resolutionBadge.Background(SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(50, 255, 255, 255)));
    m_resolutionBadge.CornerRadius(CornerRadius{ 4 });
    m_resolutionBadge.Padding(Thickness{ 6, 2, 6, 2 });
    m_resolutionBadge.Margin(Thickness{ 10, 0, 0, 0 });
    m_resolutionBadge.VerticalAlignment(VerticalAlignment::Center);
    m_resolutionBadge.HorizontalAlignment(HorizontalAlignment::Left);
    m_resolutionBadge.Visibility(Visibility::Collapsed);

    m_resolutionText = TextBlock();
    m_resolutionText.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    m_resolutionText.FontSize(10);
    m_resolutionText.FontWeight(winrt::Windows::UI::Text::FontWeights::Bold());
    m_resolutionBadge.Child(m_resolutionText);
    
    // Let's place resolution badge inside a StackPanel with title
    StackPanel titlePanel;
    titlePanel.Orientation(Orientation::Horizontal);
    titlePanel.Children().Append(m_titleLabel);
    titlePanel.Children().Append(m_resolutionBadge);
    m_topBar.SetColumn(titlePanel, 0);
    m_topBar.Children().Append(titlePanel);

    // Top Bar Right Controls (Cloud Remote, Open File, Settings)
    StackPanel topControls;
    topControls.Orientation(Orientation::Horizontal);
    topControls.HorizontalAlignment(HorizontalAlignment::Right);
    m_topBar.SetColumn(topControls, 2);
    m_topBar.Children().Append(topControls);

    Button remoteBtn = Button();
    remoteBtn.Content(winrt::box_value(L"☁"));
    remoteBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    remoteBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    remoteBtn.BorderThickness(Thickness{ 0 });
    remoteBtn.Margin(Thickness{ 0, 0, 5, 0 });
    remoteBtn.Click([this](auto const&, auto const&) { onRcloneClicked(); });
    topControls.Children().Append(remoteBtn);

    Button openBtn = Button();
    openBtn.Content(winrt::box_value(L"📂"));
    openBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    openBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    openBtn.BorderThickness(Thickness{ 0 });
    openBtn.Margin(Thickness{ 0, 0, 5, 0 });
    openBtn.Click([this](auto const&, auto const&) {
        // Open file picker
        winrt::Windows::Storage::Pickers::FileOpenPicker picker;
        picker.as<IInitializeWithWindow>()->Initialize(m_hwndVideo);
        picker.FileTypeFilter().Append(L"*");
        picker.PickSingleFileAsync().Completed([this](auto const& op, auto const& status) {
            if (status == winrt::Windows::Foundation::AsyncStatus::Completed) {
                auto file = op.GetResults();
                if (file) {
                    m_dispatcherQueue.TryEnqueue([this, path = file.Path()]() {
                        openFile(path.c_str());
                    });
                }
            }
        });
    });
    topControls.Children().Append(openBtn);

    Button settingsBtn = Button();
    settingsBtn.Content(winrt::box_value(L"⚙"));
    settingsBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    settingsBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    settingsBtn.BorderThickness(Thickness{ 0 });
    settingsBtn.Click([this](auto const&, auto const&) { onSettingsClicked(); });
    topControls.Children().Append(settingsBtn);

    m_rootGrid.Children().Append(m_topBar);

    // Setup Bottom Bar
    m_bottomBar = Grid();
    m_bottomBar.Height(85);
    m_bottomBar.VerticalAlignment(VerticalAlignment::Bottom);
    m_bottomBar.Padding(Thickness{ 15, 5, 15, 10 });
    
    // Bottom Bar dark gradient background
    LinearGradientBrush bottomBg;
    GradientStop bStop1, bStop2;
    bStop1.Color(winrt::Windows::UI::ColorHelper::FromArgb(0, 20, 20, 20));
    bStop1.Offset(0.0);
    bStop2.Color(winrt::Windows::UI::ColorHelper::FromArgb(200, 20, 20, 20));
    bStop2.Offset(1.0);
    bottomBg.GradientStops().Append(bStop1);
    bottomBg.GradientStops().Append(bStop2);
    m_bottomBar.Background(bottomBg);

    RowDefinition r1, r2;
    r1.Height(GridLength{ 1, GridUnitType::Auto });
    r2.Height(GridLength{ 1, GridUnitType::Star });
    m_bottomBar.RowDefinitions().Append(r1);
    m_bottomBar.RowDefinitions().Append(r2);

    // Timeline seek slider
    m_seekSlider = Slider();
    m_seekSlider.Minimum(0);
    m_seekSlider.Maximum(100);
    m_seekSlider.Value(0);
    m_seekSlider.Margin(Thickness{ 0, 0, 0, 5 });
    m_seekSlider.VerticalAlignment(VerticalAlignment::Center);
    
    // ValueChanged callback
    m_seekSlider.RegisterPropertyChangedCallback(RangeBase::ValueProperty(), [this](auto const& sender, auto const& dp) {
        // Seek only when user interacts (not programmatic updates)
        // Check if slider is being focused / active
    });
    
    // Set pointer callbacks for seek
    m_seekSlider.PointerCaptureLost([this](auto const&, auto const&) {
        onSliderMoved(m_seekSlider.Value());
    });

    m_bottomBar.SetRow(m_seekSlider, 0);
    m_bottomBar.Children().Append(m_seekSlider);

    // Bottom controls grid
    Grid controlsGrid = Grid();
    ColumnDefinition c1, c2, c3;
    c1.Width(GridLength{ 1, GridUnitType::Star });
    c2.Width(GridLength{ 1, GridUnitType::Auto });
    c3.Width(GridLength{ 1, GridUnitType::Star });
    controlsGrid.ColumnDefinitions().Append(c1);
    controlsGrid.ColumnDefinitions().Append(c2);
    controlsGrid.ColumnDefinitions().Append(c3);

    // Left controls: Time indications
    StackPanel timePanel;
    timePanel.Orientation(Orientation::Horizontal);
    timePanel.VerticalAlignment(VerticalAlignment::Center);
    controlsGrid.SetColumn(timePanel, 0);
    controlsGrid.Children().Append(timePanel);

    m_timeLabel = TextBlock();
    m_timeLabel.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::LightGray()));
    m_timeLabel.FontSize(12);
    m_timeLabel.Text(L"00:00");
    timePanel.Children().Append(m_timeLabel);

    TextBlock divider = TextBlock();
    divider.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::Gray()));
    divider.FontSize(12);
    divider.Text(L" / ");
    timePanel.Children().Append(divider);

    m_remainingTimeLabel = TextBlock();
    m_remainingTimeLabel.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::Gray()));
    m_remainingTimeLabel.FontSize(12);
    m_remainingTimeLabel.Text(L"00:00");
    timePanel.Children().Append(m_remainingTimeLabel);

    // Center controls: Playback controls (Rewind, Play/Pause, Forward)
    StackPanel playbackPanel;
    playbackPanel.Orientation(Orientation::Horizontal);
    playbackPanel.HorizontalAlignment(HorizontalAlignment::Center);
    controlsGrid.SetColumn(playbackPanel, 1);
    controlsGrid.Children().Append(playbackPanel);

    Button rewindBtn = Button();
    rewindBtn.Content(winrt::box_value(L"⏪"));
    rewindBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    rewindBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    rewindBtn.BorderThickness(Thickness{ 0 });
    rewindBtn.Click([this](auto const&, auto const&) { m_mpv->seek(-10.0); });
    playbackPanel.Children().Append(rewindBtn);

    m_playPauseBtn = Button();
    m_playPauseBtn.Content(winrt::box_value(L"▶"));
    m_playPauseBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    m_playPauseBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    m_playPauseBtn.BorderThickness(Thickness{ 0 });
    m_playPauseBtn.FontSize(18);
    m_playPauseBtn.Margin(Thickness{ 10, 0, 10, 0 });
    m_playPauseBtn.Click([this](auto const&, auto const&) { onPlayPauseClicked(); });
    playbackPanel.Children().Append(m_playPauseBtn);

    Button forwardBtn = Button();
    forwardBtn.Content(winrt::box_value(L"⏩"));
    forwardBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    forwardBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    forwardBtn.BorderThickness(Thickness{ 0 });
    forwardBtn.Click([this](auto const&, auto const&) { m_mpv->seek(10.0); });
    playbackPanel.Children().Append(forwardBtn);

    // Right controls: Volume, Speed, Shader preset, Fullscreen
    StackPanel rightPanel;
    rightPanel.Orientation(Orientation::Horizontal);
    rightPanel.HorizontalAlignment(HorizontalAlignment::Right);
    controlsGrid.SetColumn(rightPanel, 2);
    controlsGrid.Children().Append(rightPanel);

    m_muteBtn = Button();
    m_muteBtn.Content(winrt::box_value(L"🔊"));
    m_muteBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    m_muteBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    m_muteBtn.BorderThickness(Thickness{ 0 });
    m_muteBtn.Click([this](auto const&, auto const&) { onMuteClicked(); });
    rightPanel.Children().Append(m_muteBtn);

    m_volumeSlider = Slider();
    m_volumeSlider.Minimum(0);
    m_volumeSlider.Maximum(100);
    m_volumeSlider.Value(m_volume);
    m_volumeSlider.Width(80);
    m_volumeSlider.Margin(Thickness{ 5, 0, 15, 0 });
    m_volumeSlider.VerticalAlignment(VerticalAlignment::Center);
    m_volumeSlider.ValueChanged([this](auto const&, RangeBaseValueChangedEventArgs const& args) {
        onVolumeChanged(args.NewValue());
    });
    rightPanel.Children().Append(m_volumeSlider);

    Button speedBtn = Button();
    speedBtn.Content(winrt::box_value(L"1.0x"));
    speedBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    speedBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    speedBtn.BorderThickness(Thickness{ 0 });
    speedBtn.Margin(Thickness{ 0, 0, 10, 0 });
    speedBtn.Click([this, speedBtn](auto const&, auto const&) {
        // Cycle playback speed
        double currentSpeed = m_mpv->getPropertyDouble("speed");
        double newSpeed = 1.0;
        if (currentSpeed >= 1.0 && currentSpeed < 1.25) newSpeed = 1.25;
        else if (currentSpeed >= 1.25 && currentSpeed < 1.5) newSpeed = 1.5;
        else if (currentSpeed >= 1.5 && currentSpeed < 2.0) newSpeed = 2.0;
        else newSpeed = 1.0;
        
        m_mpv->setProperty("speed", std::to_string(newSpeed));
        speedBtn.Content(winrt::box_value(std::to_wstring(newSpeed).substr(0, 3) + L"x"));
    });
    rightPanel.Children().Append(speedBtn);

    Button fullscreenBtn = Button();
    fullscreenBtn.Content(winrt::box_value(L"⛶"));
    fullscreenBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    fullscreenBtn.Background(SolidColorBrush(winrt::Windows::UI::Colors::Transparent()));
    fullscreenBtn.BorderThickness(Thickness{ 0 });
    fullscreenBtn.Click([this](auto const&, auto const&) { toggleFullscreen(); });
    rightPanel.Children().Append(fullscreenBtn);

    m_bottomBar.SetRow(controlsGrid, 1);
    m_bottomBar.Children().Append(controlsGrid);

    m_rootGrid.Children().Append(m_bottomBar);

    m_hudWindow.Content(m_rootGrid);

    // Setup hover timer to hide UI automatically after 3 seconds
    m_hudTimer = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread().CreateTimer();
    m_hudTimer.Interval(std::chrono::seconds(3));
    m_hudTimer.Tick([this](auto const&, auto const&) {
        hideHudElements();
    });

    m_rootGrid.PointerMoved([this](auto const&, auto const&) {
        showHudElements();
        m_hudTimer.Stop();
        m_hudTimer.Start();
    });

    m_hudTimer.Start();
}

void MainWindow::updateHudData(double pos)
{
    m_position = pos;
    m_timeLabel.Text(formatTime(pos));
    
    if (m_duration > 0.0) {
        m_remainingTimeLabel.Text(formatTime(m_duration - pos));
        
        // Prevent infinite value change triggers by adjusting slider value
        double val = (pos / m_duration) * 100.0;
        m_seekSlider.Value(val);
    }
}

void MainWindow::updateDuration(double dur)
{
    m_duration = dur;
    m_remainingTimeLabel.Text(formatTime(dur));
}

void MainWindow::onPlayPauseClicked()
{
    m_isPlaying = !m_isPlaying;
    if (m_isPlaying) {
        m_mpv->play();
    } else {
        m_mpv->pause();
    }
}

void MainWindow::onSliderMoved(double val)
{
    if (m_duration <= 0.0) return;
    double targetPos = (val / 100.0) * m_duration;
    m_mpv->seek(targetPos, true, true);
}

void MainWindow::onVolumeChanged(double val)
{
    m_volume = static_cast<int>(val);
    m_mpv->setVolume(m_volume);
    updateVolumeIcon();
}

void MainWindow::onMuteClicked()
{
    m_isMuted = !m_isMuted;
    m_mpv->setMute(m_isMuted);
    updateVolumeIcon();
}

void MainWindow::updateVolumeIcon()
{
    if (m_isMuted) {
        m_muteBtn.Content(winrt::box_value(L"🔇"));
    } else if (m_volume == 0) {
        m_muteBtn.Content(winrt::box_value(L"🔇"));
    } else if (m_volume < 40) {
        m_muteBtn.Content(winrt::box_value(L"🔈"));
    } else if (m_volume < 80) {
        m_muteBtn.Content(winrt::box_value(L"🔉"));
    } else {
        m_muteBtn.Content(winrt::box_value(L"🔊"));
    }
    m_volumeSlider.Value(m_volume);
}

void MainWindow::onSettingsClicked()
{
    // Launch Settings window
    auto settings = std::make_shared<SettingsWindow>();
    settings->show();
}

void MainWindow::onRcloneClicked()
{
    // Launch Cloud browser
    auto rclone = std::make_shared<RcloneBrowser>();
    rclone->fileSelected([this, rclone](std::wstring const& url) {
        rclone->close();
        openFile(url);
    });
    rclone->show();
}

void MainWindow::openRcloneBrowserDirectly()
{
    m_dispatcherQueue.TryEnqueue([this]() {
        onRcloneClicked();
    });
}

void MainWindow::openFile(const std::wstring& filePath)
{
    m_currentFilePath = filePath;
    m_mpv->loadFile(filePath);
    
    // Extract filename
    size_t lastSlash = filePath.find_last_of(L"\\/");
    std::wstring fileName = (lastSlash == std::wstring::npos) ? filePath : filePath.substr(lastSlash + 1);
    m_titleLabel.Text(fileName);

    m_isPlaying = true;
    m_playPauseBtn.Content(winrt::box_value(L"⏸"));
}

void MainWindow::setAnime4kPreset(const std::wstring& preset)
{
    std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
    std::string presetStr = converter.to_bytes(preset);
    
    // We map Anime4K preset setting directly to libmpv shaders property
    m_mpv->setProperty("glsl-shaders", "~~/shaders/Anime4K_" + presetStr + ".glsl");
}

void MainWindow::suppressWelcome()
{
    m_welcomeSuppressed = true;
}

bool MainWindow::shouldShowWelcome() const
{
    return !m_welcomeSuppressed;
}

void MainWindow::show()
{
    ShowWindow(m_hwndVideo, SW_SHOW);
    m_hudWindow.Activate();
}

void MainWindow::executeCommand(const std::wstring& command)
{
    // Handle IPC forwarded filename / URL command
    openFile(command);
}

void MainWindow::showHudElements()
{
    if (!m_hudVisible) {
        m_hudVisible = true;
        m_topBar.Opacity(1.0);
        m_bottomBar.Opacity(1.0);
        
        // Restore cursor
        while (ShowCursor(TRUE) < 0);
    }
}

void MainWindow::hideHudElements()
{
    if (m_hudVisible) {
        m_hudVisible = false;
        m_topBar.Opacity(0.0);
        m_bottomBar.Opacity(0.0);
        
        // Hide cursor
        while (ShowCursor(FALSE) >= 0);
    }
}

std::wstring MainWindow::formatTime(double seconds)
{
    if (seconds < 0) seconds = 0;
    int totalSecs = static_cast<int>(seconds);
    int hrs = totalSecs / 3600;
    int mins = (totalSecs % 3600) / 60;
    int secs = totalSecs % 60;

    wchar_t buf[64];
    if (hrs > 0) {
        swprintf_s(buf, L"%02d:%02d:%02d", hrs, mins, secs);
    } else {
        swprintf_s(buf, L"%02d:%02d", mins, secs);
    }
    return buf;
}

void MainWindow::toggleFullscreen()
{
    m_isFullscreen = !m_isFullscreen;
    if (m_isFullscreen) {
        m_wpPrev.length = sizeof(WINDOWPLACEMENT);
        GetWindowPlacement(m_hwndVideo, &m_wpPrev);
        
        DWORD dwStyle = GetWindowLong(m_hwndVideo, GWL_STYLE);
        SetWindowLong(m_hwndVideo, GWL_STYLE, dwStyle & ~WS_OVERLAPPEDWINDOW);
        
        HMONITOR hMonitor = MonitorFromWindow(m_hwndVideo, MONITOR_DEFAULTTOPRIMARY);
        MONITORINFO mi = { sizeof(MONITORINFO) };
        if (GetMonitorInfo(hMonitor, &mi)) {
            SetWindowPos(m_hwndVideo, HWND_TOP,
                mi.rcMonitor.left, mi.rcMonitor.top,
                mi.rcMonitor.right - mi.rcMonitor.left,
                mi.rcMonitor.bottom - mi.rcMonitor.top,
                SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
        }
    } else {
        DWORD dwStyle = GetWindowLong(m_hwndVideo, GWL_STYLE);
        SetWindowLong(m_hwndVideo, GWL_STYLE, dwStyle | WS_OVERLAPPEDWINDOW);
        SetWindowPlacement(m_hwndVideo, &m_wpPrev);
    }
    
    // Sync HUD size & pos
    syncHudPosition();
}

LRESULT CALLBACK MainWindow::WndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    MainWindow* pThis = nullptr;
    if (msg == WM_NCCREATE) {
        CREATESTRUCT* pCreate = reinterpret_cast<CREATESTRUCT*>(lParam);
        pThis = reinterpret_cast<MainWindow*>(pCreate->lpCreateParams);
        SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(pThis));
    } else {
        pThis = reinterpret_cast<MainWindow*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
    }

    if (pThis) {
        return pThis->handleMessage(hwnd, msg, wParam, lParam);
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}

LRESULT MainWindow::handleMessage(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    switch (msg) {
        case WM_SIZE: {
            int width = LOWORD(lParam);
            int height = HIWORD(lParam);
            if (m_hwndChildVideo) {
                SetWindowPos(m_hwndChildVideo, nullptr, 0, 0, width, height, SWP_NOZORDER | SWP_NOMOVE);
            }
            syncHudPosition();
            break;
        }
        case WM_MOVE:
        case WM_WINDOWPOSCHANGED:
            syncHudPosition();
            break;
        case WM_KEYDOWN:
        case WM_SYSKEYDOWN: {
            int key = static_cast<int>(wParam);
            switch (key) {
                case VK_SPACE:
                    onPlayPauseClicked();
                    break;
                case VK_LEFT:
                    m_mpv->seek(-5.0);
                    break;
                case VK_RIGHT:
                    m_mpv->seek(5.0);
                    break;
                case VK_UP:
                    m_volume = (std::min)(m_volume + 5, 200);
                    m_mpv->setVolume(m_volume);
                    updateVolumeIcon();
                    break;
                case VK_DOWN:
                    m_volume = (std::max)(m_volume - 5, 0);
                    m_mpv->setVolume(m_volume);
                    updateVolumeIcon();
                    break;
                case 'M':
                case 'm':
                    onMuteClicked();
                    break;
                case 'F':
                case 'f':
                    toggleFullscreen();
                    break;
                case VK_ESCAPE:
                    if (m_isFullscreen) {
                        toggleFullscreen();
                    }
                    break;
                default:
                    break;
            }
            break;
        }
        case WM_COPYDATA: {
            PCOPYDATASTRUCT pcds = reinterpret_cast<PCOPYDATASTRUCT>(lParam);
            if (pcds && pcds->dwData == 1) {
                wchar_t* cmd = reinterpret_cast<wchar_t*>(pcds->lpData);
                executeCommand(cmd);
            }
            return TRUE;
        }
        case WM_LBUTTONDBLCLK:
            toggleFullscreen();
            break;
        case WM_LBUTTONDOWN:
            onPlayPauseClicked();
            break;
        case WM_CLOSE:
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProc(hwnd, msg, wParam, lParam);
}
