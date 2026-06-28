#include "App.xaml.h"
#include "App.xaml.g.hpp"
#include "MainWindow.xaml.h"
#include <winrt/Microsoft.UI.Xaml.h>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;

namespace winrt::GlassPlayer::implementation
{
    App::App()
    {
        InitializeComponent();
#if _DEBUG
        UnhandledException([](IInspectable const&, UnhandledExceptionEventArgs const& e)
        {
            if (IsDebuggerPresent())
            {
                auto errorMessage = e.Message();
                __debugbreak();
            }
        });
#endif
    }

    void App::OnLaunched(LaunchActivatedEventArgs const&)
    {
        auto window = winrt::make<MainWindow>();
        Microsoft::UI::Xaml::Application::Current().Resources().Insert(winrt::box_value(L"MainWindow"), window);
        window.Activate();
    }
}

#include "App.g.cpp"

