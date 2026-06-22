cmake_minimum_required(VERSION 3.20)

project(GlassPlayerWindows VERSION 1.0 LANGUAGES CXX)

set(CMAKE_VS_NUGET_PACKAGE_RESTORE ON)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
string(TOLOWER "${CMAKE_GENERATOR_PLATFORM}" _gen_platform_lower)

# Windows App SDK and C++/WinRT are managed via NuGet package references below


# Add mpv dependency
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(MPV QUIET mpv)
endif()

# Fallback for Windows builds if pkg-config isn't available
if (NOT MPV_FOUND)
    set(MPV_VENDOR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/mpv-dev)
    if (_gen_platform_lower STREQUAL "arm64")
        set(MPV_ARCH_DIR ${MPV_VENDOR_DIR}/arm64)
    else()
        set(MPV_ARCH_DIR ${MPV_VENDOR_DIR}/x64)
    endif()

    set(_mpv_include_candidates
        ${MPV_ARCH_DIR}/include
        ${MPV_VENDOR_DIR}/include
    )
    foreach(_cand IN LISTS _mpv_include_candidates)
        if (EXISTS "${_cand}/mpv/client.h")
            set(MPV_INCLUDE_DIRS ${_cand})
            break()
        endif()
    endforeach()

    set(_mpv_lib_candidates
        ${MPV_ARCH_DIR}/libmpv.lib
        ${MPV_ARCH_DIR}/libmpv.dll.a
        ${MPV_VENDOR_DIR}/libmpv.lib
        ${MPV_VENDOR_DIR}/libmpv.dll.a
    )
    foreach(_cand IN LISTS _mpv_lib_candidates)
        if (EXISTS "${_cand}")
            set(MPV_LIBRARIES "${_cand}")
            break()
        endif()
    endforeach()

    set(_mpv_dll_candidates
        ${MPV_ARCH_DIR}/libmpv-2.dll
        ${MPV_VENDOR_DIR}/libmpv-2.dll
    )
    foreach(_cand IN LISTS _mpv_dll_candidates)
        if (EXISTS "${_cand}")
            set(MPV_RUNTIME_DLL "${_cand}")
            break()
        endif()
    endforeach()

    if (NOT MPV_INCLUDE_DIRS OR NOT MPV_LIBRARIES)
        message(FATAL_ERROR "libmpv headers/libraries not found. Provide architecture-matched files under vendor/mpv-dev[/x64|/arm64].")
    endif()
endif()

# Add app icon for Windows (Removed to stick to SVG, handled programmatically)

add_executable(GlassPlayer WIN32
    main.cpp
    MainWindow.cpp
    MainWindow.h
    WelcomeWindow.cpp
    WelcomeWindow.h
    SettingsWindow.cpp
    SettingsWindow.h
    RcloneBrowser.cpp
    RcloneBrowser.h
    MpvManager.cpp
    MpvManager.h
    WinOSIntegration.cpp
    WinOSIntegration.h
    app.rc
)

set_target_properties(GlassPlayer PROPERTIES
    VS_GLOBAL_TargetPlatformMinVersion "10.0.17763.0"
)

target_include_directories(GlassPlayer PRIVATE ${MPV_INCLUDE_DIRS})
target_link_libraries(GlassPlayer PRIVATE ${MPV_LIBRARIES} d3d11.lib dxgi.lib wbemuuid.lib dxva2.lib dwmapi.lib Shlwapi.lib Pathcch.lib Microsoft.WindowsAppRuntime.Bootstrap.lib)

# Copy libmpv-2.dll to the build directory so it can be run directly from IDE
if (MPV_RUNTIME_DLL AND EXISTS "${MPV_RUNTIME_DLL}")
    add_custom_command(TARGET GlassPlayer POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${MPV_RUNTIME_DLL}"
            $<TARGET_FILE_DIR:GlassPlayer>
    )
endif()

# CPack configuration for professional installer
set(CPACK_PACKAGE_NAME "GlassPlayer")
set(CPACK_PACKAGE_VENDOR "Glass Player Team")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Glass Player - A modern media player")
if(NOT CPACK_PACKAGE_VERSION)
    set(CPACK_PACKAGE_VERSION "1.0.0")
endif()
set(CPACK_GENERATOR "NSIS")

# Professional NSIS branding and behavior
set(CPACK_PACKAGE_INSTALL_DIRECTORY "GlassPlayer")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE")
set(CPACK_NSIS_DISPLAY_NAME "Glass Player")
set(CPACK_NSIS_PACKAGE_NAME "Glass Player")
set(CPACK_NSIS_MUI_ICON "${CMAKE_CURRENT_SOURCE_DIR}/icons/app.ico")
set(CPACK_NSIS_MUI_UNIICON "${CMAKE_CURRENT_SOURCE_DIR}/icons/app.ico")
set(CPACK_NSIS_HELP_LINK "https://github.com/khr898/Glass-player-macOS")
set(CPACK_NSIS_URL_INFO_ABOUT "https://github.com/khr898/Glass-player-macOS")

# Premium NSIS installer options
set(CPACK_NSIS_WELCOME_TITLE "Welcome to Glass Player Setup")
set(CPACK_NSIS_WELCOME_TITLE_3LINES ON)
set(CPACK_NSIS_MUI_FINISHPAGE_RUN "bin\\\\GlassPlayer.exe")
set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
set(CPACK_NSIS_MODIFY_PATH OFF)
set(CPACK_NSIS_COMPRESSOR "/SOLID lzma")

# Shortcut creation
set(CPACK_NSIS_CREATE_ICONS_EXTRA "
  CreateShortCut '$DESKTOP\\\\Glass Player.lnk' '$INSTDIR\\\\bin\\\\GlassPlayer.exe'
")
set(CPACK_NSIS_DELETE_ICONS_EXTRA "
  Delete '$DESKTOP\\\\Glass Player.lnk'
")
set(CPACK_NSIS_MENU_LINKS "bin/GlassPlayer.exe" "Glass Player")

# Setup for installing dependencies (like mpv.dll and Qt DLLs)
install(TARGETS GlassPlayer DESTINATION bin)

if(WIN32)
    if (MPV_RUNTIME_DLL AND EXISTS "${MPV_RUNTIME_DLL}")
        install(FILES ${MPV_RUNTIME_DLL} DESTINATION bin)
    endif()
    
    # Windows App SDK handles its own deployment dll copying via NuGet targets

endif()

if(WIN32)
    set(CMAKE_INSTALL_SYSTEM_RUNTIME_DESTINATION bin)
    include(InstallRequiredSystemLibraries)
endif()

include(CPack)
