#include "SettingsWindow.xaml.h"
#include "SettingsWindow.xaml.g.hpp"
#include "WinOSIntegration.h"

#include <microsoft.ui.xaml.window.h>
#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Interop.h>
#include <winrt/Windows.Storage.h>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Microsoft::UI::Xaml::Controls;

namespace winrt::GlassPlayer::implementation
{
    SettingsWindow::SettingsWindow()
    {
        InitializeComponent();
        SetupWindow();
        LoadSettings();
    }

    void SettingsWindow::SetupWindow()
    {
        auto windowNative = this->try_as<IWindowNative>();
        if (windowNative) {
            windowNative->get_WindowHandle(&m_hwnd);
        }

        // Apply custom size (600x450)
        auto appWindow = winrt::Microsoft::UI::Windowing::AppWindow::GetFromWindowId(
            winrt::Microsoft::UI::GetWindowIdFromWindow(m_hwnd));
        appWindow.Resize({ 600, 450 });

        // Apply frosted glass
        WinOSIntegration::instance().applyFrostedGlass(m_hwnd);

        // Select first item by default
        SidebarList().SelectedIndex(0);
    }

    void SettingsWindow::LoadSettings()
    {
        auto settings = winrt::Windows::Storage::ApplicationData::Current().LocalSettings().Values();

        // General
        if (settings.HasKey(L"StartFullscreen")) {
            FullscreenCheck().IsChecked(unbox_value<bool>(settings.Lookup(L"StartFullscreen")));
        }
        if (settings.HasKey(L"AutoResume")) {
            AutoResumeCheck().IsChecked(unbox_value<bool>(settings.Lookup(L"AutoResume")));
        }
        if (settings.HasKey(L"PlayDrop")) {
            PlayDropCheck().IsChecked(unbox_value<bool>(settings.Lookup(L"PlayDrop")));
        }
        if (settings.HasKey(L"UpdatesCheck")) {
            UpdatesCheck().IsChecked(unbox_value<bool>(settings.Lookup(L"UpdatesCheck")));
        }

        // Video
        if (settings.HasKey(L"Hwdec")) {
            auto val = unbox_value<winrt::hstring>(settings.Lookup(L"Hwdec"));
            if (val == L"d3d11va") HwdecCombo().SelectedIndex(0);
            else if (val == L"d3d11va-copy") HwdecCombo().SelectedIndex(1);
            else if (val == L"dxva2-copy") HwdecCombo().SelectedIndex(2);
            else HwdecCombo().SelectedIndex(3);
        } else {
            HwdecCombo().SelectedIndex(0);
        }

        if (settings.HasKey(L"Vsync")) {
            VsyncCheck().IsChecked(unbox_value<bool>(settings.Lookup(L"Vsync")));
        } else {
            VsyncCheck().IsChecked(true);
        }
        if (settings.HasKey(L"Interpolation")) {
            InterpolationCheck().IsChecked(unbox_value<bool>(settings.Lookup(L"Interpolation")));
        } else {
            InterpolationCheck().IsChecked(true);
        }
    }

    void SettingsWindow::SaveSettings()
    {
        auto settings = winrt::Windows::Storage::ApplicationData::Current().LocalSettings().Values();

        // General
        settings.Insert(L"StartFullscreen", box_value(FullscreenCheck().IsChecked().GetBoolean()));
        settings.Insert(L"AutoResume", box_value(AutoResumeCheck().IsChecked().GetBoolean()));
        settings.Insert(L"PlayDrop", box_value(PlayDropCheck().IsChecked().GetBoolean()));
        settings.Insert(L"UpdatesCheck", box_value(UpdatesCheck().IsChecked().GetBoolean()));

        // Video
        if (HwdecCombo().SelectedItem()) {
            auto item = HwdecCombo().SelectedItem().as<ComboBoxItem>();
            settings.Insert(L"Hwdec", box_value(item.Content().as<winrt::hstring>()));
        }
        settings.Insert(L"Vsync", box_value(VsyncCheck().IsChecked().GetBoolean()));
        settings.Insert(L"Interpolation", box_value(InterpolationCheck().IsChecked().GetBoolean()));
    }

    void SettingsWindow::OnSidebarSelectionChanged(IInspectable const&, SelectionChangedEventArgs const&)
    {
        int index = SidebarList().SelectedIndex();

        // Toggle page Visibility based on selected index
        GeneralPage().Visibility(index == 0 ? Visibility::Visible : Visibility::Collapsed);
        VideoPage().Visibility(index == 1 ? Visibility::Visible : Visibility::Collapsed);
        AudioPage().Visibility(index == 2 ? Visibility::Visible : Visibility::Collapsed);
        SubtitlesPage().Visibility(index == 3 ? Visibility::Visible : Visibility::Collapsed);
        NetworkPage().Visibility(index == 4 ? Visibility::Visible : Visibility::Collapsed);
        ScalingPage().Visibility(index == 5 ? Visibility::Visible : Visibility::Collapsed);
        ColorPage().Visibility(index == 6 ? Visibility::Visible : Visibility::Collapsed);
        Anime4KPage().Visibility(index == 7 ? Visibility::Visible : Visibility::Collapsed);
        ShortcutsPage().Visibility(index == 8 ? Visibility::Visible : Visibility::Collapsed);
    }

    void SettingsWindow::OnSettingCheckClicked(IInspectable const&, RoutedEventArgs const&)
    {
        SaveSettings();
    }

    void SettingsWindow::OnSettingComboChanged(IInspectable const&, SelectionChangedEventArgs const&)
    {
        SaveSettings();
    }

    void SettingsWindow::OnSettingTextChanged(IInspectable const&, TextChangedEventArgs const&)
    {
        SaveSettings();
    }

    void SettingsWindow::OnSettingSliderChanged(IInspectable const&, winrt::Microsoft::UI::Xaml::Controls::Primitives::RangeBaseValueChangedEventArgs const&)
    {
        SaveSettings();
    }
}

#include "SettingsWindow.g.cpp"

