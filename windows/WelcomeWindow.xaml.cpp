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
#include <winrt/Windows.ApplicationModel.DataTransfer.h>

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

        // WinUI 3: extend XAML into title bar area (no system title bar strip)
        ExtendsContentIntoTitleBar(true);

        auto appWindow = winrt::Microsoft::UI::Windowing::AppWindow::GetFromWindowId(
            winrt::Microsoft::UI::GetWindowIdFromWindow(m_hwnd));

        // Fixed-size dialog
        if (auto presenter = appWindow.Presenter().try_as<winrt::Microsoft::UI::Windowing::OverlappedPresenter>()) {
            presenter.IsResizable(false);
            presenter.IsMaximizable(false);
            presenter.IsMinimizable(false);
        }

        // Set size and center on screen
        double dpi = GetDpiForWindow(m_hwnd);
        float scale = static_cast<float>(dpi) / 96.0f;
        int32_t width = static_cast<int32_t>(520 * scale);
        int32_t height = static_cast<int32_t>(390 * scale);
        appWindow.Resize({ width, height });

        auto displayArea = winrt::Microsoft::UI::Windowing::DisplayArea::GetFromWindowId(
            appWindow.Id(), winrt::Microsoft::UI::Windowing::DisplayAreaFallback::Nearest);
        auto wa = displayArea.WorkArea();
        appWindow.Move({ wa.X + (wa.Width - width) / 2, wa.Y + (wa.Height - height) / 2 });

        // Apply frosted glass (Mica/Acrylic backdrop)
        WinOSIntegration::instance().applyFrostedGlass(m_hwnd);

        // Set window icon
        HICON hIcon = LoadIconW(GetModuleHandleW(nullptr), L"IDI_APP_ICON");
        if (hIcon) {
            SendMessageW(m_hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(hIcon));
            SendMessageW(m_hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(hIcon));
        }
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


    void WelcomeWindow::OnDragOver(IInspectable const&, DragEventArgs const& e)
    {
        using namespace winrt::Windows::ApplicationModel::DataTransfer;
        if (e.DataView().Contains(StandardDataFormats::StorageItems())) {
            e.AcceptedOperation(DataPackageOperation::Copy);
            e.DragUIOverride().Caption(L"Open file");
        }
    }

    void WelcomeWindow::OnDrop(IInspectable const&, DragEventArgs const& e)
    {
        auto op = e.DataView().GetStorageItemsAsync();
        op.Completed([this](auto&& asyncOp, auto&&) {
            auto items = asyncOp.GetResults();
            if (items.Size() > 0) {
                if (auto file = items.GetAt(0).try_as<winrt::Windows::Storage::StorageFile>()) {
                    m_selectedFile = file.Path().c_str();
                    m_accepted = true;
                    DispatcherQueue().TryEnqueue([this]() {
                        Close();
                    });
                }
            }
        });
    }
}

#include "WelcomeWindow.g.cpp"

