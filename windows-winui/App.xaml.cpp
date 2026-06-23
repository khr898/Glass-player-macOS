#include "App.xaml.h"
#include "MainWindow.xaml.h"
#include <winrt/Microsoft.UI.Xaml.h>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;

namespace winrt::GlassPlayer::implementation
{
    App::App()
    {
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
        window.Activate();
    }
}
