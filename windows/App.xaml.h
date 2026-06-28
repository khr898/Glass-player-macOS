#pragma once

#include <unknwn.h>
#include "App.g.h"

namespace winrt::GlassPlayer::implementation
{
    struct App : AppT<App, winrt::GlassPlayer::App>
    {
        using composable = winrt::GlassPlayer::App;

        App();

        void OnLaunched(winrt::Microsoft::UI::Xaml::LaunchActivatedEventArgs const&);
    };
}

namespace winrt::GlassPlayer::factory_implementation
{
    struct App : AppT<App, implementation::App>
    {
    };
}
