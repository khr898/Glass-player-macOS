#pragma once

#include <unknwn.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <windows.h>
#undef GetCurrentTime

#include "WelcomeWindow.g.h"
#include <winrt/Microsoft.UI.Xaml.h>
#include <string>

namespace winrt::GlassPlayer::implementation
{
    struct WelcomeWindow : WelcomeWindowT<WelcomeWindow>
    {
        WelcomeWindow();

        void OnCloseClicked(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& args);
        void OnOpenFileClicked(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& args);
        void OnRemoteClicked(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::RoutedEventArgs const& args);
        void OnDragOver(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::DragEventArgs const& args);
        void OnDrop(winrt::Windows::Foundation::IInspectable const& sender, winrt::Microsoft::UI::Xaml::DragEventArgs const& args);

        std::wstring SelectedFile() const { return m_selectedFile; }
        bool RemoteClicked() const { return m_remoteClicked; }
        bool Accepted() const { return m_accepted; }

    private:
        void SetupWindow();

        HWND m_hwnd{ nullptr };
        std::wstring m_selectedFile;
        bool m_remoteClicked{ false };
        bool m_accepted{ false };
    };
}

namespace winrt::GlassPlayer::factory_implementation
{
    struct WelcomeWindow : WelcomeWindowT<WelcomeWindow, implementation::WelcomeWindow>
    {
    };
}
