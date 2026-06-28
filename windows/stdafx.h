#pragma once

// Windows SDK headers
#include <unknwn.h>
#include <windows.h>
#undef GetCurrentTime

// C++/WinRT base and system projections
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.Web.Http.h>
#include <winrt/Windows.System.Threading.h>

// WinUI 3 Windowing and Interop
#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Microsoft.UI.Interop.h>
#include <winrt/Microsoft.UI.Dispatching.h>

// WinUI 3 XAML Framework
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Data.h>
#include <winrt/Microsoft.UI.Xaml.Interop.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Media.Animation.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>

// Windows Implementation Library
#include <wil/cppwinrt.h>
#include <wil/resource.h>

// Standard C++ libraries
#include <memory>
#include <string>
#include <vector>
#include <cmath>
#include <iostream>
