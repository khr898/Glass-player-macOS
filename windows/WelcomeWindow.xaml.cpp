#include "WelcomeWindow.xaml.h"
#include "WelcomeWindow.xaml.g.hpp"
#include "WinOSIntegration.h"

#include <microsoft.ui.xaml.window.h>
#include <shobjidl.h>
#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Interop.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Foundation.h>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;
using namespace winrt::Windows::Storage::Pickers;
using namespace winrt::Windows::Foundation;

namespace winrt::GlassPlayer::implementation
{
    WelcomeWindow::WelcomeWindow()
    {
        InitializeComponent();
        SetupWindow();
    }

    void WelcomeWindow::SetupWindow()
    {
        auto windowNative = this->try_as<IWindowNative>();
        if (windowNative) {
            windowNative->get_WindowHandle(&m_hwnd);
        }

        // Apply custom size (520x390)
        auto appWindow = winrt::Microsoft::UI::Windowing::AppWindow::GetFromWindowId(
            winrt::Microsoft::UI::GetWindowIdFromWindow(m_hwnd));
        
        // Remove frame/caption to make it look borderless like the Qt version
        LONG style = GetWindowLong(m_hwnd, GWL_STYLE);
        style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        SetWindowLong(m_hwnd, GWL_STYLE, style);

        // Center on screen
        appWindow.Resize({ 520, 390 });
        
        // Apply frosted glass
        WinOSIntegration::instance().applyFrostedGlass(m_hwnd);
    }

    void WelcomeWindow::OnCloseClicked(IInspectable const&, RoutedEventArgs const&)
    {
        Close();
    }

    void WelcomeWindow::OnOpenFileClicked(IInspectable const&, RoutedEventArgs const&)
    {
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

        auto pickOperation = picker.PickSingleFileAsync();
        pickOperation.Completed([this](auto&& op, auto&& status) {
            if (status == AsyncStatus::Completed) {
                auto file = op.GetResults();
                if (file) {
                    m_selectedFile = file.Path().c_str();
                    m_accepted = true;
                    DispatcherQueue().TryEnqueue([this]() {
                        Close();
                    });
                }
            }
        });
    }

    void WelcomeWindow::OnRemoteClicked(IInspectable const&, RoutedEventArgs const&)
    {
        m_remoteClicked = true;
        m_accepted = true;
        Close();
    }
}

#include "WelcomeWindow.g.cpp"

