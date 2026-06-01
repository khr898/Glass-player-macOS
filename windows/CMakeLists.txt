cmake_minimum_required(VERSION 3.20)

project(GlassPlayerWindows VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
string(TOLOWER "${CMAKE_GENERATOR_PLATFORM}" _gen_platform_lower)

find_package(Qt6 COMPONENTS Core Gui Widgets OpenGLWidgets Network Svg SvgWidgets REQUIRED)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

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
    MpvWidget.cpp
    MpvWidget.h
    WinOSIntegration.cpp
    WinOSIntegration.h
    app.rc
    resources.qrc
)

target_include_directories(GlassPlayer PRIVATE ${MPV_INCLUDE_DIRS})
target_link_libraries(GlassPlayer PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets Qt6::OpenGLWidgets Qt6::Network Qt6::Svg Qt6::SvgWidgets ${MPV_LIBRARIES} d3d11.lib dxgi.lib wbemuuid.lib dxva2.lib)

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
set(CPACK_PACKAGE_VERSION "1.0.0")
set(CPACK_GENERATOR "NSIS")

# Professional NSIS branding
set(CPACK_PACKAGE_INSTALL_DIRECTORY "GlassPlayer")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE")
set(CPACK_NSIS_DISPLAY_NAME "Glass Player")
set(CPACK_NSIS_PACKAGE_NAME "Glass Player")
set(CPACK_NSIS_MUI_ICON "${CMAKE_CURRENT_SOURCE_DIR}/icons/app.ico")
set(CPACK_NSIS_MUI_UNIICON "${CMAKE_CURRENT_SOURCE_DIR}/icons/app.ico")
set(CPACK_NSIS_HELP_LINK "https://github.com/khr898/Glass-player-macOS")
set(CPACK_NSIS_URL_INFO_ABOUT "https://github.com/khr898/Glass-player-macOS")

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
    
    get_target_property(_qmake_executable Qt6::qmake IMPORTED_LOCATION)
    get_filename_component(_qt_bin_dir "${_qmake_executable}" DIRECTORY)
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt HINTS "${_qt_bin_dir}")
    
    if(WINDEPLOYQT_EXECUTABLE)
        install(CODE "execute_process(COMMAND ${WINDEPLOYQT_EXECUTABLE} --no-translations --no-compiler-runtime --no-opengl-sw \"\${CMAKE_INSTALL_PREFIX}/bin/GlassPlayer.exe\")")
    endif()
endif()

include(CPack)
