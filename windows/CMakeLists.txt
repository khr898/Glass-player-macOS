cmake_minimum_required(VERSION 3.16)

project(GlassPlayerWindows VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 COMPONENTS Core Gui Widgets OpenGLWidgets Network REQUIRED)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Add mpv dependency
# In a real build environment, we'd find libmpv.
# We'll use find_package or add_library with imported targets later.
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(MPV QUIET mpv)
endif()

# Fallback for Windows Actions if pkg-config isn't available
if (NOT MPV_FOUND)
    set(MPV_INCLUDE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/mpv-dev/include)
    set(MPV_LIBRARIES ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/mpv-dev/libmpv.dll.a)
endif()

# Add app icon for Windows
if(WIN32)
    set(APP_ICON_RESOURCE ${CMAKE_CURRENT_SOURCE_DIR}/app.rc)
endif()

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
    resources.qrc
    ${APP_ICON_RESOURCE}
)

target_include_directories(GlassPlayer PRIVATE ${MPV_INCLUDE_DIRS})
target_link_libraries(GlassPlayer PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets Qt6::OpenGLWidgets Qt6::Network ${MPV_LIBRARIES} dxva2.lib wbemuuid.lib)

# Copy libmpv-2.dll to the build directory so it can be run directly from IDE
add_custom_command(TARGET GlassPlayer POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/../vendor/mpv-dev/libmpv-2.dll"
        $<TARGET_FILE_DIR:GlassPlayer>
)

# CPack configuration for professional installer
set(CPACK_PACKAGE_NAME "GlassPlayer")
set(CPACK_PACKAGE_VENDOR "Glass Player Team")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Glass Player - A modern media player")
set(CPACK_PACKAGE_VERSION "1.0.0")
set(CPACK_GENERATOR "NSIS")

# Professional NSIS branding
set(CPACK_PACKAGE_INSTALL_DIRECTORY "GlassPlayer")
set(CPACK_NSIS_MUI_ICON "${CMAKE_CURRENT_SOURCE_DIR}/app.ico")
set(CPACK_NSIS_MUI_UNIICON "${CMAKE_CURRENT_SOURCE_DIR}/app.ico")
set(CPACK_NSIS_WELCOMEFINISHPAGE_BITMAP "${CMAKE_CURRENT_SOURCE_DIR}/installer_branding.bmp")
set(CPACK_NSIS_HEADERIMAGE_BITMAP "${CMAKE_CURRENT_SOURCE_DIR}/installer_header.bmp")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE")
set(CPACK_NSIS_DISPLAY_NAME "Glass Player")
set(CPACK_NSIS_PACKAGE_NAME "Glass Player")
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
    install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/mpv-dev/libmpv-2.dll DESTINATION bin)
    
    get_target_property(_qmake_executable Qt6::qmake IMPORTED_LOCATION)
    get_filename_component(_qt_bin_dir "${_qmake_executable}" DIRECTORY)
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt HINTS "${_qt_bin_dir}")
    
    if(WINDEPLOYQT_EXECUTABLE)
        install(CODE "execute_process(COMMAND ${WINDEPLOYQT_EXECUTABLE} --no-translations --no-compiler-runtime --no-opengl-sw \"\${CMAKE_INSTALL_PREFIX}/bin/GlassPlayer.exe\")")
    endif()
endif()

include(CPack)
