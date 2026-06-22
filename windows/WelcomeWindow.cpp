#include "WelcomeWindow.h"
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Shapes.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Text.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <dwmapi.h>

struct __declspec(uuid("EECDB3DB-E257-4A86-844C-5B09F6F35B04")) IWindowNative : IUnknown
{
    virtual HRESULT __stdcall get_WindowHandle(HWND* hWnd) = 0;
};

WelcomeWindow::WelcomeWindow()
{
    m_window = winrt::Microsoft::UI::Xaml::Window();
    m_window.as<IWindowNative>()->get_WindowHandle(&m_hwnd);
    m_dispatcherQueue = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread();

    // Configure window dimensions (650x450) and center on screen
    m_window.Title(L"Glass Player - Welcome");
    auto appWindow = m_window.AppWindow();
    appWindow.Resize(winrt::Windows::Graphics::SizeInt32{ 650, 450 });

    // Enable Mica Backdrop
    winrt::Microsoft::UI::Xaml::Media::MicaBackdrop mica;
    m_window.SystemBackdrop(mica);

    // Dark Titlebar Theme
    BOOL darkMode = TRUE;
    DwmSetWindowAttribute(m_hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &darkMode, sizeof(darkMode));

    m_window.ExtendsContentIntoTitleBar(true);

    setupUi();
}

WelcomeWindow::~WelcomeWindow()
{
}

void WelcomeWindow::setupUi()
{
    using namespace winrt::Microsoft::UI::Xaml;
    using namespace winrt::Microsoft::UI::Xaml::Controls;
    using namespace winrt::Microsoft::UI::Xaml::Media;

    Grid rootGrid = Grid();
    rootGrid.Padding(Thickness{ 30, 40, 30, 30 });

    RowDefinition r1, r2, r3;
    r1.Height(GridLength{ 1, GridUnitType::Auto });
    r2.Height(GridLength{ 1, GridUnitType::Star });
    r3.Height(GridLength{ 1, GridUnitType::Auto });
    rootGrid.RowDefinitions().Append(r1);
    rootGrid.RowDefinitions().Append(r2);
    rootGrid.RowDefinitions().Append(r3);

    // Title area
    StackPanel header;
    header.Orientation(Orientation::Vertical);
    header.Margin(Thickness{ 0, 10, 0, 20 });
    rootGrid.SetRow(header, 0);

    TextBlock title = TextBlock();
    title.Text(L"Glass Player");
    title.FontSize(32);
    title.FontWeight(winrt::Windows::UI::Text::FontWeights::SemiBold());
    title.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    header.Children().Append(title);

    TextBlock subtitle = TextBlock();
    subtitle.Text(L"A lightweight, high-performance media player");
    subtitle.FontSize(13);
    subtitle.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::Gray()));
    subtitle.Margin(Thickness{ 2, 4, 0, 0 });
    header.Children().Append(subtitle);

    rootGrid.Children().Append(header);

    // Drag and Drop Area
    Border dropBorder = Border();
    dropBorder.BorderBrush(SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(80, 255, 255, 255)));
    dropBorder.BorderThickness(Thickness{ 2 });
    dropBorder.CornerRadius(CornerRadius{ 8 });
    dropBorder.Background(SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(20, 255, 255, 255)));
    dropBorder.Margin(Thickness{ 0, 0, 0, 20 });
    rootGrid.SetRow(dropBorder, 1);

    Grid dropGrid = Grid();
    dropGrid.HorizontalAlignment(HorizontalAlignment::Center);
    dropGrid.VerticalAlignment(VerticalAlignment::Center);

    StackPanel dropContent;
    dropContent.Orientation(Orientation::Vertical);
    dropContent.HorizontalAlignment(HorizontalAlignment::Center);

    TextBlock dropIcon = TextBlock();
    dropIcon.Text(L"📥");
    dropIcon.FontSize(48);
    dropIcon.HorizontalAlignment(HorizontalAlignment::Center);
    dropIcon.Margin(Thickness{ 0, 0, 0, 10 });
    dropContent.Children().Append(dropIcon);

    TextBlock dropText = TextBlock();
    dropText.Text(L"Drag & drop a media file here to start playing");
    dropText.FontSize(15);
    dropText.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::LightGray()));
    dropText.HorizontalAlignment(HorizontalAlignment::Center);
    dropContent.Children().Append(dropText);

    dropGrid.Children().Append(dropContent);
    dropBorder.Child(dropGrid);

    // Wire Drag and Drop
    dropBorder.AllowDrop(true);
    dropBorder.DragOver([](auto const&, DragEventArgs const& e) {
        e.AcceptedOperation(winrt::Windows::ApplicationModel::DataTransfer::DataPackageOperation::Copy);
    });
    
    dropBorder.Drop([this](auto const&, DragEventArgs const& e) {
        if (e.DataView().Contains(winrt::Windows::ApplicationModel::DataTransfer::StandardDataFormats::StorageItems())) {
            e.DataView().GetStorageItemsAsync().Completed([this](auto const& op, auto const& status) {
                if (status == winrt::Windows::Foundation::AsyncStatus::Completed) {
                    auto items = op.GetResults();
                    if (items.Size() > 0) {
                        auto file = items.GetAt(0).as<winrt::Windows::Storage::IStorageFile>();
                        if (file) {
                            m_dispatcherQueue.TryEnqueue([this, path = file.Path()]() {
                                if (m_fileOpenedCallback) m_fileOpenedCallback(path.c_str());
                            });
                        }
                    }
                }
            });
        }
    });

    rootGrid.Children().Append(dropBorder);

    // Buttons at bottom
    StackPanel btnPanel;
    btnPanel.Orientation(Orientation::Horizontal);
    btnPanel.HorizontalAlignment(HorizontalAlignment::Center);
    rootGrid.SetRow(btnPanel, 2);

    Button openFileBtn = Button();
    openFileBtn.Content(winrt::box_value(L"Open File"));
    openFileBtn.Width(130);
    openFileBtn.Height(36);
    openFileBtn.Margin(Thickness{ 0, 0, 15, 0 });
    
    // Premium style (accent color)
    openFileBtn.Background(SolidColorBrush(winrt::Windows::UI::ColorHelper::FromArgb(255, 0, 120, 215)));
    openFileBtn.Foreground(SolidColorBrush(winrt::Windows::UI::Colors::White()));
    
    openFileBtn.Click([this](auto const&, auto const&) {
        winrt::Windows::Storage::Pickers::FileOpenPicker picker;
        picker.as<IInitializeWithWindow>()->Initialize(m_hwnd);
        picker.FileTypeFilter().Append(L"*");
        picker.PickSingleFileAsync().Completed([this](auto const& op, auto const& status) {
            if (status == winrt::Windows::Foundation::AsyncStatus::Completed) {
                auto file = op.GetResults();
                if (file) {
                    m_dispatcherQueue.TryEnqueue([this, path = file.Path()]() {
                        if (m_fileOpenedCallback) m_fileOpenedCallback(path.c_str());
                    });
                }
            }
        });
    });
    btnPanel.Children().Append(openFileBtn);

    Button rcloneBtn = Button();
    rcloneBtn.Content(winrt::box_value(L"Cloud Streams"));
    rcloneBtn.Width(130);
    rcloneBtn.Height(36);
    rcloneBtn.Click([this](auto const&, auto const&) {
        if (m_openRcloneBrowserCallback) {
            m_openRcloneBrowserCallback();
        }
    });
    btnPanel.Children().Append(rcloneBtn);

    rootGrid.Children().Append(btnPanel);

    m_window.Content(rootGrid);
}

void WelcomeWindow::show()
{
    m_window.Activate();
}

void WelcomeWindow::close()
{
    m_window.Close();
}
