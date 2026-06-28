#include "MainWindow.xaml.h"
#include "MainWindow.xaml.g.hpp"
#include "WelcomeWindow.xaml.h"
#include "SettingsWindow.xaml.h"
#include "RcloneBrowser.xaml.h"
#include "WinOSIntegration.h"

#include <microsoft.ui.xaml.window.h>
#include <shobjidl.h>
#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Interop.h>
#include <iostream>
#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Xaml.Hosting.h>
#include <winrt/Microsoft.UI.Input.h>
#include <winrt/Microsoft.Graphics.Canvas.Effects.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.Effects.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.Imaging.h>

#include <cmath>
#include <string>
#include <sstream>
#include <iomanip>
#include <vector>
#include <stdexcept>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;
using namespace winrt::Microsoft::UI::Xaml::Input;
using namespace winrt::Microsoft::UI::Xaml::Media::Imaging;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Storage;
using namespace winrt::Windows::Storage::Pickers;

// Helper function to convert std::wstring to UTF-8 std::string
static std::string to_utf8(const std::wstring& wstr) {
    if (wstr.empty()) return "";
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), NULL, 0, NULL, NULL);
    std::string strTo(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), &strTo[0], size_needed, NULL, NULL);
    return strTo;
}

static std::wstring to_wide(const std::string& str) {
    if (str.empty()) return L"";
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

namespace winrt::GlassPlayer::implementation
{
    MainWindow::MainWindow()
    {
        try {
            InitializeComponent();
        } catch (winrt::hresult_error const& ex) {
            FILE* f = nullptr;
            if (_wfopen_s(&f, L"Z:\\Glass-player\\crash.log", L"a") == 0 && f) {
                fwprintf(f, L"Crash in MainWindow::InitializeComponent (hresult_error): %s (0x%08X)\n", ex.message().c_str(), ex.code().value);
                fclose(f);
            }
            throw;
        }

        try {
            SetupWindow();
        } catch (winrt::hresult_error const& ex) {
            FILE* f = nullptr;
            if (_wfopen_s(&f, L"Z:\\Glass-player\\crash.log", L"a") == 0 && f) {
                fwprintf(f, L"Crash in MainWindow::SetupWindow (hresult_error): %s (0x%08X)\n", ex.message().c_str(), ex.code().value);
                fclose(f);
            }
            throw;
        }

        try {
            InitializePlayer();
        } catch (winrt::hresult_error const& ex) {
            FILE* f = nullptr;
            if (_wfopen_s(&f, L"Z:\\Glass-player\\crash.log", L"a") == 0 && f) {
                fwprintf(f, L"Crash in MainWindow::InitializePlayer (hresult_error): %s (0x%08X)\n", ex.message().c_str(), ex.code().value);
                fclose(f);
            }
            throw;
        } catch (std::exception const& ex) {
            FILE* f = nullptr;
            if (_wfopen_s(&f, L"Z:\\Glass-player\\crash.log", L"a") == 0 && f) {
                fprintf(f, "Crash in MainWindow::InitializePlayer (std::exception): %s\n", ex.what());
                fclose(f);
            }
            throw;
        }


    }

    MainWindow::~MainWindow()
    {
        if (m_renderHost) {
            m_renderHost->Shutdown();
        }
    }

    void MainWindow::SetupWindow()
    {
        auto windowNative = this->try_as<IWindowNative>();
        if (windowNative) {
            windowNative->get_WindowHandle(&m_hwnd);
        }

        Title(L"Glass Player");
        ExtendsContentIntoTitleBar(true);
        SetTitleBar(TopBar());

        auto appWindow = winrt::Microsoft::UI::Windowing::AppWindow::GetFromWindowId(
            winrt::Microsoft::UI::GetWindowIdFromWindow(m_hwnd));
        appWindow.Resize({ 1280, 720 });

        Root().PointerMoved([this](auto&& sender, PointerRoutedEventArgs const& args) {
            OnPointerMoved(sender, args);
        });
        Root().KeyDown([this](auto&& sender, KeyRoutedEventArgs const& args) {
            OnKeyDown(sender, args);
        });
    }

    void MainWindow::InitializePlayer()
    {
        m_renderHost = std::make_shared<RenderHost>(VideoPanel());
        SetupCallbacks();

        // Trigger InitGL on Loaded
        VideoPanel().Loaded([this](auto&&, auto&&) {
            try {
                m_renderHost->InitGL();
            } catch (const std::exception& ex) {
                std::wcerr << L"GL Init failed: " << to_wide(ex.what()) << std::endl;
            }
        });
    }

    void MainWindow::SetupCallbacks()
    {
        m_renderHost->setOnPositionChanged([this](double position) {
            DispatcherQueue().TryEnqueue([this, position]() {
                if (!m_isSeeking) {
                    SeekSlider().Value(position);
                    CurrentTimeLabel().Text(formatTime(position));
                    RemainingTimeLabel().Text(formatTime(m_duration - position));
                }
            });
        });

        m_renderHost->setOnDurationChanged([this](double duration) {
            DispatcherQueue().TryEnqueue([this, duration]() {
                m_duration = duration;
                SeekSlider().Maximum(duration > 0 ? duration : 1000000);
                RemainingTimeLabel().Text(formatTime(duration));
            });
        });

        m_renderHost->setOnPauseChanged([this](bool paused) {
            DispatcherQueue().TryEnqueue([this, paused]() {
                m_isPlaying = !paused;
                PlayPauseIcon().Source(SvgImageSource(Uri(m_isPlaying ? L"ms-appx:///Assets/icons/pause.svg" : L"ms-appx:///Assets/icons/play.svg")));
            });
        });

        m_renderHost->setOnFileLoaded([this]() {
            DispatcherQueue().TryEnqueue([this]() {
                updateResolutionBadge();

                // Get current volume
                std::string volStr = m_renderHost->getPropertyString("volume");
                if (!volStr.empty()) {
                    m_volume = std::stoi(volStr);
                    VolumeSlider().Value(m_volume);
                    VolumeHoverSlider().Value(m_volume);
                }
                
                std::string muteStr = m_renderHost->getPropertyString("mute");
                m_isMuted = (muteStr == "yes");
                updateVolumeIcon(m_volume, m_isMuted);
            });
        });

        m_renderHost->setOnStartFile([this]() {
            DispatcherQueue().TryEnqueue([this]() {
                ResolutionBadge().Visibility(Visibility::Collapsed);
                SeekSlider().Value(0);
                CurrentTimeLabel().Text(L"00:00");
                RemainingTimeLabel().Text(L"00:00");
            });
        });
    }

    void MainWindow::OnPanelSizeChanged(IInspectable const&, SizeChangedEventArgs const&)
    {
        if (m_renderHost) {
            m_renderHost->OnPanelSizeChanged();
        }
    }

    void MainWindow::OnCompositionScaleChanged(SwapChainPanel const&, IInspectable const&)
    {
        if (m_renderHost) {
            m_renderHost->OnPanelSizeChanged();
        }
    }

    void MainWindow::OnBottomBarSizeChanged(IInspectable const&, SizeChangedEventArgs const&)
    {
        LayoutBottomBar();
    }

    void MainWindow::SetGeom(FrameworkElement const& element, double x, double y, double w, double h)
    {
        Canvas::SetLeft(element, x);
        Canvas::SetTop(element, y);
        element.Width(w);
        element.Height(h);
    }

    void MainWindow::LayoutBottomBar()
    {
        double bw = BottomCanvas().ActualWidth();
        if (bw <= 0) return;

        // seek row
        SetGeom(CurrentTimeLabel(), 14, 8, 60, 20);
        SetGeom(RemainingTimeLabel(), bw - 14 - 60, 8, 60, 20);
        SetGeom(SeekSlider(), 80, 8, bw - 160, 20);

        int btnY = 48;
        // center group
        int ppW = 40;
        int ppX = static_cast<int>((bw - ppW) / 2);
        SetGeom(PlayPauseBtn(), ppX, btnY - 5, ppW, 40);
        int prevX = ppX - 6 - 30;     SetGeom(PrevBtn(), prevX, btnY, 30, 30);
        int rewindX = prevX - 4 - 30; SetGeom(RewindBtn(), rewindX, btnY, 30, 30);
        int nextX = ppX + ppW + 6;    SetGeom(NextBtn(), nextX, btnY, 30, 30);
        int fwdX = nextX + 30 + 4;    SetGeom(ForwardBtn(), fwdX, btnY, 30, 30);

        // left group
        SetGeom(SubtitleBtn(), 14, btnY, 30, 30);
        SetGeom(AudioBtn(), 14 + 30 + 6, btnY, 30, 30);
        SetGeom(ShaderBtn(), 14 + 30 + 6 + 30 + 6, btnY, 30, 30);

        // right group
        int fsX = static_cast<int>(bw - 14 - 30);  SetGeom(FullscreenBtn(), fsX, btnY, 30, 30);
        int aspX = fsX - 6 - 30;      SetGeom(AspectBtn(), aspX, btnY, 30, 30);
        int spdX = aspX - 6 - 32;     SetGeom(SpeedBtn(), spdX, btnY, 32, 30);
        int volSX = spdX - 8 - 70;    SetGeom(VolumeSlider(), volSX, btnY + 5, 70, 20);
        int volBX = volSX - 6 - 30;   SetGeom(VolumeBtn(), volBX, btnY, 30, 30);
    }

    void MainWindow::openFile(const std::wstring& file)
    {
        if (m_renderHost) {
            m_renderHost->loadFile(file);
        }
    }

    void MainWindow::executeCommand(const std::wstring& command)
    {
        openFile(command);
    }

    std::wstring MainWindow::formatTime(double seconds)
    {
        if (seconds < 0) seconds = 0;
        int total_secs = static_cast<int>(seconds);
        int hours = total_secs / 3600;
        int mins = (total_secs % 3600) / 60;
        int secs = total_secs % 60;

        std::wstringstream ss;
        if (hours > 0) {
            ss << hours << L":" << std::setw(2) << std::setfill(L'0') << mins << L":" << std::setw(2) << std::setfill(L'0') << secs;
        } else {
            ss << std::setw(2) << std::setfill(L'0') << mins << L":" << std::setw(2) << std::setfill(L'0') << secs;
        }
        return ss.str();
    }

    void MainWindow::updateVolumeIcon(int volume, bool muted)
    {
        std::wstring iconName = L"volume_high.svg";
        if (muted || volume == 0) {
            iconName = L"volume_mute.svg";
        } else if (volume < 50) {
            iconName = L"volume_mid.svg";
        }

        VolumeIcon().Source(SvgImageSource(Uri(L"ms-appx:///Assets/icons/" + iconName)));
        VolumeBarIcon().Source(SvgImageSource(Uri(L"ms-appx:///Assets/icons/" + iconName)));
    }

    void MainWindow::showHud()
    {
        TopBar().Visibility(Visibility::Visible);
        BottomBar().Visibility(Visibility::Visible);

        // Cancel existing timer and restart
        if (m_hudTimer) {
            m_hudTimer.Cancel();
        }

        m_hudTimer = winrt::Windows::System::Threading::ThreadPoolTimer::CreateTimer(
            [this](auto&&) {
                DispatcherQueue().TryEnqueue([this]() {
                    hideHud();
                });
            },
            winrt::Windows::Foundation::TimeSpan(std::chrono::seconds(3))
        );
    }

    void MainWindow::hideHud()
    {
        TopBar().Visibility(Visibility::Collapsed);
        BottomBar().Visibility(Visibility::Collapsed);
    }

    void MainWindow::OnPointerMoved(IInspectable const&, PointerRoutedEventArgs const& args)
    {
        showHud();

        auto point = args.GetCurrentPoint(Root());
        auto position = point.Position();
        double mw = VideoPanel().ActualWidth();
        double mh = VideoPanel().ActualHeight();

        // Edge Hover reveal
        bool dragL = false; // We can verify if thumb is down if needed
        bool dragR = false;

        // Hide when over top/bottom bars or outside panel (similar to Qt)
        if (position.Y < 44 || position.Y > (mh - 106)) {
            BrightnessBar().Visibility(Visibility::Collapsed);
            VolumeBar().Visibility(Visibility::Collapsed);
            return;
        }

        BrightnessBar().Visibility((dragL || position.X < mw * 0.10) ? Visibility::Visible : Visibility::Collapsed);
        VolumeBar().Visibility((dragR || position.X > mw * 0.90) ? Visibility::Visible : Visibility::Collapsed);
    }

    void MainWindow::OnKeyDown(IInspectable const&, KeyRoutedEventArgs const& args)
    {
        auto key = args.Key();
        if (key == winrt::Windows::System::VirtualKey::Space) {
            OnPlayPauseClicked(nullptr, nullptr);
            args.Handled(true);
        } else if (key == winrt::Windows::System::VirtualKey::Left) {
            m_renderHost->seek(-5);
            args.Handled(true);
        } else if (key == winrt::Windows::System::VirtualKey::Right) {
            m_renderHost->seek(5);
            args.Handled(true);
        } else if (key == winrt::Windows::System::VirtualKey::Escape) {
            if (m_isFullscreen) {
                OnFullscreenClicked(nullptr, nullptr);
                args.Handled(true);
            }
        }
    }

    // Controls Action Implementations
    void MainWindow::OnPlayPauseClicked(IInspectable const&, RoutedEventArgs const&)
    {
        if (m_isPlaying) {
            m_renderHost->pause();
        } else {
            m_renderHost->play();
        }
    }

    void MainWindow::OnPrevClicked(IInspectable const&, RoutedEventArgs const&)
    {
        m_renderHost->setProperty("playlist-prev", "");
    }

    void MainWindow::OnNextClicked(IInspectable const&, RoutedEventArgs const&)
    {
        m_renderHost->setProperty("playlist-next", "");
    }

    void MainWindow::OnRewindClicked(IInspectable const&, RoutedEventArgs const&)
    {
        m_renderHost->seek(-5);
    }

    void MainWindow::OnForwardClicked(IInspectable const&, RoutedEventArgs const&)
    {
        m_renderHost->seek(5);
    }

    void MainWindow::OnMuteClicked(IInspectable const&, RoutedEventArgs const&)
    {
        m_renderHost->toggleMute();
        m_isMuted = !m_isMuted;
        updateVolumeIcon(m_volume, m_isMuted);
    }

    void MainWindow::OnSeekSliderValueChanged(IInspectable const&, winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const& args)
    {
        if (m_isSeeking) {
            CurrentTimeLabel().Text(formatTime(args.NewValue()));
            RemainingTimeLabel().Text(formatTime(m_duration - args.NewValue()));
        }
    }

    void MainWindow::OnSeekSliderCaptureLost(IInspectable const&, PointerRoutedEventArgs const&)
    {
        m_isSeeking = false;
        m_renderHost->setPropertyDouble("time-pos", SeekSlider().Value());
    }

    void MainWindow::OnVolumeSliderValueChanged(IInspectable const&, winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const& args)
    {
        m_volume = static_cast<int>(args.NewValue());
        m_renderHost->setVolume(m_volume);
        updateVolumeIcon(m_volume, m_isMuted);
        VolumeHoverSlider().Value(m_volume);
    }

    void MainWindow::OnVolumeHoverSliderValueChanged(IInspectable const&, winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const& args)
    {
        m_volume = static_cast<int>(args.NewValue());
        m_renderHost->setVolume(m_volume);
        updateVolumeIcon(m_volume, m_isMuted);
        VolumeSlider().Value(m_volume);
    }

    void MainWindow::OnBrightnessSliderValueChanged(IInspectable const&, winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const& args)
    {
        // Interface with system OS integration
        double level = args.NewValue();
        WinOSIntegration::instance().setSystemBrightness(level / 100.0f);
    }

    void MainWindow::OnUrlClicked(IInspectable const&, RoutedEventArgs const&)
    {
        if (UrlEdit().Visibility() == Visibility::Visible) {
            UrlEdit().Visibility(Visibility::Collapsed);
        } else {
            UrlEdit().Visibility(Visibility::Visible);
            UrlEdit().Focus(FocusState::Programmatic);
        }
    }

    void MainWindow::OnUrlEditKeyDown(IInspectable const&, KeyRoutedEventArgs const& args)
    {
        if (args.Key() == winrt::Windows::System::VirtualKey::Enter) {
            std::wstring url = UrlEdit().Text().c_str();
            if (!url.empty()) {
                openFile(url);
                UrlEdit().Visibility(Visibility::Collapsed);
            }
        }
    }

    void MainWindow::OnOpenClicked(IInspectable const&, RoutedEventArgs const&)
    {
        // Simple File Open Picker implementation
        FileOpenPicker picker;
        auto initializeWithWindow = picker.as<IInitializeWithWindow>();
        initializeWithWindow->Initialize(m_hwnd);

        picker.ViewMode(PickerViewMode::List);
        picker.SuggestedStartLocation(PickerLocationId::VideosLibrary);
        picker.FileTypeFilter().Append(L".mp4");
        picker.FileTypeFilter().Append(L".mkv");
        picker.FileTypeFilter().Append(L".avi");
        picker.FileTypeFilter().Append(L".mov");
        picker.FileTypeFilter().Append(L"*");

        // Background thread call
        auto pickOperation = picker.PickSingleFileAsync();
        pickOperation.Completed([this](auto&& op, auto&& status) {
            if (status == AsyncStatus::Completed) {
                auto file = op.GetResults();
                if (file) {
                    DispatcherQueue().TryEnqueue([this, file]() {
                        openFile(file.Path().c_str());
                    });
                }
            }
        });
    }

    void MainWindow::OnRemoteClicked(IInspectable const&, RoutedEventArgs const&)
    {
        // Remote browser dialog
    }

    void MainWindow::OnSettingsClicked(IInspectable const&, RoutedEventArgs const&)
    {
        // Settings dialog
    }

    std::vector<MainWindow::TrackInfo> MainWindow::getTracks()
    {
        std::vector<TrackInfo> list;
        std::string countStr = m_renderHost->getPropertyString("track-list/count");
        if (countStr.empty()) return list;
        int count = std::stoi(countStr);
        for (int i = 0; i < count; ++i) {
            std::string prefix = "track-list/" + std::to_string(i) + "/";
            TrackInfo info;
            info.id = std::stoi(m_renderHost->getPropertyString(prefix + "id"));
            info.type = to_wide(m_renderHost->getPropertyString(prefix + "type"));
            info.label = to_wide(m_renderHost->getPropertyString(prefix + "title"));
            if (info.label.empty()) {
                info.label = to_wide(m_renderHost->getPropertyString(prefix + "lang"));
            }
            if (info.label.empty()) {
                info.label = L"Track " + std::to_wstring(info.id);
            }
            info.selected = m_renderHost->getPropertyString(prefix + "selected") == "yes";
            list.push_back(info);
        }
        return list;
    }

    void MainWindow::setSubtitleTrack(int id)
    {
        m_renderHost->setProperty("sid", std::to_string(id));
    }

    void MainWindow::setAudioTrack(int id)
    {
        m_renderHost->setProperty("aid", std::to_string(id));
    }

    void MainWindow::addExternalSubtitle()
    {
        // Trigger file picker and pass subtitle track
    }

    void MainWindow::addExternalAudio()
    {
        // Trigger file picker and pass audio track
    }

    void MainWindow::OnSubtitleClicked(IInspectable const& sender, RoutedEventArgs const&)
    {
        // Build sub-tracks menu
        MenuFlyout flyout;
        auto tracks = getTracks();
        
        // Add "Off" item
        MenuFlyoutItem offItem;
        offItem.Text(L"Off");
        offItem.Click([this](auto&&, auto&&) { setSubtitleTrack(0); });
        flyout.Items().Append(offItem);

        for (const auto& track : tracks) {
            if (track.type == L"sub") {
                ToggleMenuFlyoutItem item;
                item.Text(track.label);
                item.IsChecked(track.selected);
                item.Click([this, id = track.id](auto&&, auto&&) {
                    setSubtitleTrack(id);
                });
                flyout.Items().Append(item);
            }
        }

        MenuFlyoutSeparator sep;
        flyout.Items().Append(sep);

        MenuFlyoutItem addExt;
        addExt.Text(L"Add External...");
        addExt.Click([this](auto&&, auto&&) { addExternalSubtitle(); });
        flyout.Items().Append(addExt);

        flyout.ShowAt(sender.as<FrameworkElement>());
    }

    void MainWindow::OnAudioClicked(IInspectable const& sender, RoutedEventArgs const&)
    {
        // Build audio tracks menu
        MenuFlyout flyout;
        auto tracks = getTracks();

        for (const auto& track : tracks) {
            if (track.type == L"audio") {
                ToggleMenuFlyoutItem item;
                item.Text(track.label);
                item.IsChecked(track.selected);
                item.Click([this, id = track.id](auto&&, auto&&) {
                    setAudioTrack(id);
                });
                flyout.Items().Append(item);
            }
        }

        MenuFlyoutSeparator sep;
        flyout.Items().Append(sep);

        MenuFlyoutItem addExt;
        addExt.Text(L"Add External...");
        addExt.Click([this](auto&&, auto&&) { addExternalAudio(); });
        flyout.Items().Append(addExt);

        flyout.ShowAt(sender.as<FrameworkElement>());
    }

    void MainWindow::OnShaderClicked(IInspectable const& sender, RoutedEventArgs const&)
    {
        MenuFlyout flyout;

        std::vector<std::wstring> presets = { L"ModeA", L"ModeB", L"ModeC", L"ModeAA", L"ModeBB", L"ModeCA", L"Off" };
        for (const auto& preset : presets) {
            MenuFlyoutItem item;
            item.Text(preset);
            item.Click([this, preset](auto&&, auto&&) {
                m_currentShaderPreset = preset;
                if (preset == L"Off") {
                    m_renderHost->setProperty("glsl-shaders", "");
                } else {
                    std::string wStr = m_renderHost->getPropertyString("width");
                    std::string hStr = m_renderHost->getPropertyString("height");
                    int sourceMax = 0;
                    if (!wStr.empty() && !hStr.empty())
                        sourceMax = std::max(std::stoi(wStr), std::stoi(hStr));
                    int dispMax = displayMaxDimension();
                    bool upscale = sourceMax > 0 && dispMax > 0 && (sourceMax * 100 < dispMax * 97);
                    if (upscale)
                        m_renderHost->setProperty("glsl-shaders", "shaders/" + to_utf8(preset) + ".glsl");
                    else
                        m_renderHost->setProperty("glsl-shaders", "");
                }
                updateResolutionBadge();
            });
            flyout.Items().Append(item);
        }

        flyout.ShowAt(sender.as<FrameworkElement>());
    }

    int MainWindow::displayMaxDimension() const
    {
        HMONITOR hMon = MonitorFromWindow(m_hwnd, MONITOR_DEFAULTTONEAREST);
        if (!hMon) return 0;
        MONITORINFO mi{ sizeof(mi) };
        if (!GetMonitorInfo(hMon, &mi)) return 0;
        int w = mi.rcMonitor.right  - mi.rcMonitor.left;
        int h = mi.rcMonitor.bottom - mi.rcMonitor.top;
        return std::max(w, h);
    }

    void MainWindow::updateResolutionBadge()
    {
        std::string wStr = m_renderHost ? m_renderHost->getPropertyString("width")  : "";
        std::string hStr = m_renderHost ? m_renderHost->getPropertyString("height") : "";
        if (wStr.empty() || hStr.empty()) {
            ResolutionBadge().Visibility(Visibility::Collapsed);
            return;
        }
        int vw = std::stoi(wStr);
        int vh = std::stoi(hStr);
        int sourceMax = std::max(vw, vh);
        int dispMax   = displayMaxDimension();
        bool upscaling = !m_currentShaderPreset.empty()
                      && m_currentShaderPreset != L"Off"
                      && sourceMax > 0 && dispMax > 0
                      && (sourceMax * 100 < dispMax * 97);
        if (upscaling) {
            double f = std::min(4.0, double(dispMax) / sourceMax);
            int uw = int(vw * f), uh = int(vh * f);
            ResolutionText().Text(to_wide(wStr + "x" + hStr + " ➔ "
                + std::to_string(uw) + "x" + std::to_string(uh)));
        } else {
            ResolutionText().Text(to_wide(wStr + "x" + hStr));
        }
        ResolutionBadge().Visibility(Visibility::Visible);
    }

    void MainWindow::OnAspectClicked(IInspectable const& sender, RoutedEventArgs const&)
    {
        MenuFlyout flyout;
        std::vector<std::wstring> aspects = { L"auto", L"16:9", L"16:10", L"4:3", L"21:9", L"2.35:1" };
        for (const auto& aspect : aspects) {
            MenuFlyoutItem item;
            item.Text(aspect);
            item.Click([this, aspect](auto&&, auto&&) {
                m_renderHost->setProperty("video-aspect-override", to_utf8(aspect));
            });
            flyout.Items().Append(item);
        }
        flyout.ShowAt(sender.as<FrameworkElement>());
    }

    void MainWindow::OnSpeedClicked(IInspectable const& sender, RoutedEventArgs const&)
    {
        MenuFlyout flyout;
        std::vector<double> speeds = { 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0, 4.0 };
        for (double speed : speeds) {
            MenuFlyoutItem item;
            std::wstringstream ss;
            ss << speed << L"x";
            item.Text(ss.str());
            item.Click([this, speed](auto&&, auto&&) {
                m_renderHost->setPropertyDouble("speed", speed);
                std::wstringstream ssBtn;
                ssBtn << speed << L"x";
                SpeedBtn().Content(box_value(ssBtn.str()));
            });
            flyout.Items().Append(item);
        }
        flyout.ShowAt(sender.as<FrameworkElement>());
    }

    void MainWindow::OnFullscreenClicked(IInspectable const&, RoutedEventArgs const&)
    {
        winrt::Microsoft::UI::Windowing::AppWindow appWindow = winrt::Microsoft::UI::Windowing::AppWindow::GetFromWindowId(
            winrt::Microsoft::UI::GetWindowIdFromWindow(m_hwnd));

        if (m_isFullscreen) {
            appWindow.SetPresenter(winrt::Microsoft::UI::Windowing::AppWindowPresenterKind::Default);
            m_isFullscreen = false;
            FullscreenIcon().Source(SvgImageSource(Uri(L"ms-appx:///Assets/icons/fullscreen.svg")));
        } else {
            appWindow.SetPresenter(winrt::Microsoft::UI::Windowing::AppWindowPresenterKind::FullScreen);
            m_isFullscreen = true;
            FullscreenIcon().Source(SvgImageSource(Uri(L"ms-appx:///Assets/icons/fullscreen_exit.svg")));
        }
    }

    
}

#include "MainWindow.g.cpp"

