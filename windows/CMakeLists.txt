cmake_minimum_required(VERSION 3.16)

project(GlassPlayerWindows VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 COMPONENTS Core Gui Widgets OpenGLWidgets REQUIRED)

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
    set(MPV_LIBRARIES ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/mpv-dev/lib/mpv.lib)
endif()

add_executable(GlassPlayer
    main.cpp
    MainWindow.cpp
    MainWindow.h
    MpvWidget.cpp
    MpvWidget.h
    resources.qrc
)

target_include_directories(GlassPlayer PRIVATE ${MPV_INCLUDE_DIRS})
target_link_libraries(GlassPlayer PRIVATE Qt6::Core Qt6::Gui Qt6::Widgets Qt6::OpenGLWidgets ${MPV_LIBRARIES})

# CPack configuration for installer
set(CPACK_PACKAGE_NAME "GlassPlayer")
set(CPACK_PACKAGE_VENDOR "Glass Player Team")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Glass Player - A modern media player")
set(CPACK_PACKAGE_VERSION "1.0.0")
set(CPACK_GENERATOR "NSIS")

# Setup for installing dependencies (like mpv.dll and Qt DLLs)
# This will be refined in the github actions workflow
install(TARGETS GlassPlayer DESTINATION bin)

include(CPack)
