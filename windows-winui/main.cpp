#include <unknwn.h>
#include <windows.h>
#undef GetCurrentTime
#include <mddbootstrap.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.ApplicationModel.Activation.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/GlassPlayer.h>
#include <wil/resource.h>
#include <thread>
#include <iostream>

#include "App.xaml.h"
#include "MainWindow.xaml.h"
#include "WelcomeWindow.xaml.h"

using namespace winrt;
using namespace winrt::Microsoft::Windows::AppLifecycle;

int __stdcall wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    // 1. Initialize Windows App SDK Bootstrapper for Unpackaged deployment
    // Major/Minor version 1.5: 0x00010005
    const UINT32 majorMinorVersion = 0x00010005;
    HRESULT hr = MddBootstrapInitialize2(majorMinorVersion, nullptr, PACKAGE_VERSION{ 0 }, MddBootstrapInitializeOptions_OnError_FailFast);
    if (FAILED(hr))
    {
        MessageBoxW(nullptr, L"Failed to initialize Windows App SDK runtime. Please ensure the runtime is installed.", L"Glass Player - Error", MB_OK | MB_ICONERROR);
        return hr;
    }

    // 2. Initialize COM Apartment
    winrt::init_apartment(winrt::apartment_type::single_threaded);

    // 3. Single-Instance Check and Activation Redirection
    auto args = AppInstance::GetCurrent().GetActivatedEventArgs();
    auto keyInstance = AppInstance::FindOrRegisterForKey(L"GlassPlayerUniqueInstanceKey");

    if (!keyInstance.IsCurrent())
    {
        // Redirect arguments to the existing running instance
        wil::unique_event redirectEvent;
        redirectEvent.create(wil::EventOptions::ManualReset);

        std::thread([&]() {
            keyInstance.RedirectActivationToAsync(args).get();
            redirectEvent.SetEvent();
        }).detach();

        // Non-blocking wait to process UI messages while redirecting
        HANDLE events[] = { redirectEvent.get() };
        DWORD waitResult;
        do {
            waitResult = MsgWaitForMultipleObjects(1, events, FALSE, INFINITE, QS_ALLINPUT);
            if (waitResult == WAIT_OBJECT_0 + 1) {
                MSG msg;
                while (PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
                    TranslateMessage(&msg);
                    DispatchMessage(&msg);
                }
            }
        } while (waitResult != WAIT_OBJECT_0);

        // Clean up bootstrapper and exit second instance
        MddBootstrapShutdown();
        return 0;
    }

    // 4. Register activation handler on primary instance
    keyInstance.Activated([](auto&&, AppActivationArguments const& args) {
        // Redirection event fired. Retrieve the active window and forward the file path.
        auto window = winrt::Microsoft::UI::Xaml::Application::Current().Resources().Lookup(box_value(L"MainWindow")).as<winrt::GlassPlayer::MainWindow>();
        if (window) {
            auto kind = args.Kind();
            if (kind == ExtendedActivationKind::Launch) {
                auto launchArgs = args.Data().as<winrt::Windows::ApplicationModel::Activation::LaunchActivatedEventArgs>();
                if (launchArgs) {
                    std::wstring file = launchArgs.Arguments().c_str();
                    auto impl = winrt::get_self<winrt::GlassPlayer::implementation::MainWindow>(window);
                    window.DispatcherQueue().TryEnqueue([impl, file]() {
                        impl->openFile(file);
                    });
                }
            }
        }
    });

    // 5. Run the XAML application
    ::winrt::Microsoft::UI::Xaml::Application::Start([](auto&&) {
        ::winrt::make<winrt::GlassPlayer::implementation::App>();
    });

    // 6. Clean up Bootstrapper
    MddBootstrapShutdown();
    return 0;
}
