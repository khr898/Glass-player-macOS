#include "App.xaml.h"
#include "App.xaml.g.hpp"
#include "MainWindow.xaml.h"
#include "WelcomeWindow.xaml.h"
#include <winrt/Microsoft.UI.Xaml.h>

using namespace winrt;
using namespace winrt::Microsoft::UI::Xaml;

namespace winrt::GlassPlayer::implementation
{
    App::App()
    {
        InitializeComponent();

        UnhandledException([](IInspectable const&, UnhandledExceptionEventArgs const& e)
        {
            if (IsDebuggerPresent())
            {
                auto errorMessage = e.Message();
                __debugbreak();
            }
        });
    }

    void App::OnLaunched(LaunchActivatedEventArgs const& launchArgs)
    {
        // If launched with file/command arguments, skip welcome and open directly
        auto cmdLine = launchArgs.Arguments();
        if (!cmdLine.empty())
        {
            auto window = winrt::make<MainWindow>();
            Microsoft::UI::Xaml::Application::Current().Resources().Insert(winrt::box_value(L"MainWindow"), window);
            window.Activate();
            auto impl = winrt::get_self<implementation::MainWindow>(window);
            window.DispatcherQueue().TryEnqueue([impl, file = std::wstring(cmdLine.c_str())]() {
                impl->openFile(file);
            });
        }
        else
        {
            // Show welcome window first; create main window only on accept
            auto welcome = winrt::make<WelcomeWindow>();
            welcome.Closed([welcome](auto&&, auto&&) {
                auto impl = winrt::get_self<implementation::WelcomeWindow>(welcome);
                if (impl->Accepted())
                {
                    auto window = winrt::make<MainWindow>();
                    Microsoft::UI::Xaml::Application::Current().Resources().Insert(winrt::box_value(L"MainWindow"), window);
                    window.Activate();
                    if (!impl->SelectedFile().empty())
                    {
                        auto mainImpl = winrt::get_self<implementation::MainWindow>(window);
                        window.DispatcherQueue().TryEnqueue([mainImpl, file = impl->SelectedFile()]() {
                            mainImpl->openFile(file);
                        });
                    }
                }
                // else: no active window → app exits
            });
            welcome.Activate();
        }
    }
}

#include "App.g.cpp"

