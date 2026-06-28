#include "RenderHost.h"
#include <winrt/Windows.Foundation.h>
#include <cmath>
#include <stdexcept>
#include <iostream>

// Helper to convert get_abi to EGLNativeWindowType
#include <unknwn.h>

// ANGLE extension function pointer types
typedef EGLDisplay(EGLAPIENTRYP PFNEGLGETPLATFORMDISPLAYEXTPROC)(EGLenum platform, void* native_display, const EGLint* attrib_list);

static std::string trim(const std::string& str) {
    size_t first = str.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return "";
    size_t last = str.find_last_not_of(" \t\r\n");
    return str.substr(first, (last - first + 1));
}

static std::string to_utf8(const std::wstring& wstr) {
    if (wstr.empty()) return "";
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), NULL, 0, NULL, NULL);
    std::string strTo(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, &wstr[0], (int)wstr.size(), &strTo[0], size_needed, NULL, NULL);
    return strTo;
}

static std::wstring to_wide(const std::string& str) {
    if (str.empty()) return L"";
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

static void* get_proc_address(void* ctx, const char* name) {
    return reinterpret_cast<void*>(eglGetProcAddress(name));
}

RenderHost::RenderHost(winrt::Microsoft::UI::Xaml::Controls::SwapChainPanel const& panel)
    : m_panel(panel)
{
    m_dispatcher = panel.DispatcherQueue();
    m_mpv = mpv_create();
    if (!m_mpv) {
        throw std::runtime_error("Could not create mpv context");
    }

    // Setting options (Verbatim from Qt6 MpvWidget constructor)
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    m_hwdecMode = detectPreferredHwdec();
    mpv_set_option_string(m_mpv, "hwdec", m_hwdecMode.c_str());
    mpv_set_option_string(m_mpv, "hwdec-software-fallback", "yes");
    mpv_set_option_string(m_mpv, "hwdec-codecs", "all");

    mpv_set_option_string(m_mpv, "gpu-api", "opengl");
    mpv_set_option_string(m_mpv, "video-sync", "display-resample");
    mpv_set_option_string(m_mpv, "interpolation", "yes");

    mpv_set_option_string(m_mpv, "keep-open", "yes");
    mpv_set_option_string(m_mpv, "input-default-bindings", "yes");
    mpv_set_option_string(m_mpv, "input-vo-keyboard", "no");
    mpv_set_option_string(m_mpv, "osc", "no");
    mpv_set_option_string(m_mpv, "osd-level", "0");
    mpv_set_option_string(m_mpv, "idle", "yes");
    mpv_set_option_string(m_mpv, "force-window", "no");
    mpv_set_option_string(m_mpv, "volume-max", "200");

    mpv_set_option_string(m_mpv, "target-colorspace-hint", "yes");
    mpv_set_option_string(m_mpv, "hdr-compute-peak", "yes");
    mpv_set_option_string(m_mpv, "tone-mapping", "bt.2390");

    mpv_set_option_string(m_mpv, "ao", "wasapi");
    mpv_set_option_string(m_mpv, "audio-channels", "auto");
    mpv_set_option_string(m_mpv, "audio-spdif", "");

    if (mpv_initialize(m_mpv) < 0) {
        throw std::runtime_error("Could not initialize mpv context");
    }

    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "track-list/count", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);

    mpv_set_wakeup_callback(m_mpv, onMpvEventsWrapper, this);
}

RenderHost::~RenderHost()
{
    Shutdown();
}

void RenderHost::InitGL()
{
    if (m_glInitialized) return;

    // 1. Get eglGetPlatformDisplayEXT
    PFNEGLGETPLATFORMDISPLAYEXTPROC eglGetPlatformDisplayEXT = 
        reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(eglGetProcAddress("eglGetPlatformDisplayEXT"));
    if (!eglGetPlatformDisplayEXT) {
        throw std::runtime_error("eglGetPlatformDisplayEXT not found");
    }

    // 2. Initialize EGL display with ANGLE D3D11 type
    EGLint dispAttrs[] = {
        EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_D3D11_ANGLE,
        EGL_NONE
    };
    m_eglDisplay = eglGetPlatformDisplayEXT(EGL_PLATFORM_ANGLE_ANGLE, EGL_DEFAULT_DISPLAY, dispAttrs);
    if (m_eglDisplay == EGL_NO_DISPLAY) {
        throw std::runtime_error("Failed to get ANGLE EGL display");
    }

    if (!eglInitialize(m_eglDisplay, nullptr, nullptr)) {
        throw std::runtime_error("Failed to initialize EGL");
    }

    // 3. Choose configuration
    EGLint cfgAttrs[] = {
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_NONE
    };
    EGLint numConfigs = 0;
    if (!eglChooseConfig(m_eglDisplay, cfgAttrs, &m_cfg, 1, &numConfigs) || numConfigs == 0) {
        throw std::runtime_error("Failed to choose EGL config");
    }

    // 4. Create context (OpenGL ES 3.0)
    EGLint ctxAttrs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    m_eglCtx = eglCreateContext(m_eglDisplay, m_cfg, EGL_NO_CONTEXT, ctxAttrs);
    if (m_eglCtx == EGL_NO_CONTEXT) {
        throw std::runtime_error("Failed to create EGL context");
    }

    // 5. Create EGL window surface over the SwapChainPanel
    EGLint surfAttrs[] = { EGL_NONE };
    ::IUnknown* panelUnknown = reinterpret_cast<::IUnknown*>(winrt::get_abi(m_panel));
    m_eglSurf = eglCreateWindowSurface(m_eglDisplay, m_cfg, reinterpret_cast<EGLNativeWindowType>(panelUnknown), surfAttrs);
    if (m_eglSurf == EGL_NO_SURFACE) {
        throw std::runtime_error("Failed to create EGL window surface over SwapChainPanel");
    }

    if (!eglMakeCurrent(m_eglDisplay, m_eglSurf, m_eglSurf, m_eglCtx)) {
        throw std::runtime_error("Failed to make EGL context current");
    }

    // 6. Create mpv OpenGL render context
    mpv_opengl_init_params gl_init{ get_proc_address, nullptr };
    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_API_TYPE, const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL) },
        { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init },
        { MPV_RENDER_PARAM_INVALID, nullptr }
    };

    if (mpv_render_context_create(&m_mpv_gl, m_mpv, params) < 0) {
        throw std::runtime_error("Failed to initialize mpv GL context");
    }

    mpv_render_context_set_update_callback(m_mpv_gl, onUpdateWrapper, this);

    m_glInitialized = true;
    if (!m_pendingFileToLoad.empty()) {
        std::wstring file = m_pendingFileToLoad;
        m_pendingFileToLoad.clear();
        loadFile(file);
    }
}

void RenderHost::RenderFrame()
{
    if (!m_mpv_gl) return;

    eglMakeCurrent(m_eglDisplay, m_eglSurf, m_eglSurf, m_eglCtx);

    int w = static_cast<int>(std::round(m_panel.ActualWidth() * m_panel.CompositionScaleX()));
    int h = static_cast<int>(std::round(m_panel.ActualHeight() * m_panel.CompositionScaleY()));
    
    // Prevent 0-sized viewports
    if (w <= 0) w = 1;
    if (h <= 0) h = 1;

    glViewport(0, 0, w, h);

    mpv_opengl_fbo mpfbo{
        0, // default framebuffer for ANGLE is 0
        w,
        h,
        0
    };

    int flip_y = 1; // Constraint: must be 1

    mpv_render_param params[] = {
        { MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo },
        { MPV_RENDER_PARAM_FLIP_Y, &flip_y },
        { MPV_RENDER_PARAM_INVALID, nullptr }
    };

    mpv_render_context_render(m_mpv_gl, params);
    eglSwapBuffers(m_eglDisplay, m_eglSurf);
    mpv_render_context_report_swap(m_mpv_gl);
}

void RenderHost::OnPanelSizeChanged()
{
    if (m_glInitialized) {
        RenderFrame();
    }
}

void RenderHost::Shutdown()
{
    if (m_mpv_gl) {
        mpv_render_context_set_update_callback(m_mpv_gl, nullptr, nullptr);
        mpv_render_context_free(m_mpv_gl);
        m_mpv_gl = nullptr;
    }
    if (m_mpv) {
        mpv_set_wakeup_callback(m_mpv, nullptr, nullptr);
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
    }

    if (m_eglDisplay != EGL_NO_DISPLAY) {
        eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (m_eglSurf != EGL_NO_SURFACE) {
            eglDestroySurface(m_eglDisplay, m_eglSurf);
            m_eglSurf = EGL_NO_SURFACE;
        }
        if (m_eglCtx != EGL_NO_CONTEXT) {
            eglDestroyContext(m_eglDisplay, m_eglCtx);
            m_eglCtx = EGL_NO_CONTEXT;
        }
        eglTerminate(m_eglDisplay);
        m_eglDisplay = EGL_NO_DISPLAY;
    }
    m_glInitialized = false;
}

void RenderHost::onMpvEventsWrapper(void* ctx)
{
    auto self = static_cast<RenderHost*>(ctx);
    self->m_dispatcher.TryEnqueue([self]() {
        self->PumpEvents();
    });
}

void RenderHost::onUpdateWrapper(void* ctx)
{
    auto self = static_cast<RenderHost*>(ctx);
    self->m_dispatcher.TryEnqueue([self]() {
        self->RenderFrame();
    });
}

void RenderHost::PumpEvents()
{
    while (m_mpv) {
        mpv_event* event = mpv_wait_event(m_mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
        handleEvent(event);
    }
}

void RenderHost::handleEvent(mpv_event* event)
{
    switch (event->event_id) {
    case MPV_EVENT_START_FILE:
        m_hwdecFallbackHandled = false;
        mpv_set_property_string(m_mpv, "hwdec", m_hwdecMode.c_str());
        if (m_onStartFile) m_onStartFile();
        break;
    case MPV_EVENT_FILE_LOADED:
        applyHwdecFallbackIfNeeded();
        if (m_onFileLoaded) m_onFileLoaded();
        break;
    case MPV_EVENT_PROPERTY_CHANGE: {
        mpv_event_property* prop = static_cast<mpv_event_property*>(event->data);
        if (strcmp(prop->name, "time-pos") == 0) {
            if (prop->format == MPV_FORMAT_DOUBLE) {
                if (m_onPositionChanged) m_onPositionChanged(*(double*)prop->data);
            }
        } else if (strcmp(prop->name, "duration") == 0) {
            if (prop->format == MPV_FORMAT_DOUBLE) {
                if (m_onDurationChanged) m_onDurationChanged(*(double*)prop->data);
            }
        } else if (strcmp(prop->name, "pause") == 0) {
            if (prop->format == MPV_FORMAT_FLAG) {
                if (m_onPauseChanged) m_onPauseChanged(*(int*)prop->data != 0);
            }
        }
        break;
    }
    case MPV_EVENT_END_FILE: {
        mpv_event_end_file* eof = static_cast<mpv_event_end_file*>(event->data);
        if (eof && eof->reason == MPV_END_FILE_REASON_ERROR) {
            if (m_onPlaybackError) {
                std::string errStr = mpv_error_string(eof->error);
                m_onPlaybackError(to_wide(errStr));
            }
        } else {
            if (m_onEofReached) m_onEofReached();
        }
        break;
    }
    case MPV_EVENT_PLAYBACK_RESTART:
        if (m_onPlaybackRestarted) m_onPlaybackRestarted();
        break;
    default:
        break;
    }
}

void RenderHost::loadFile(const std::wstring& filePath)
{
    if (!m_glInitialized) {
        m_pendingFileToLoad = filePath;
        return;
    }

    std::string pathUtf8 = to_utf8(filePath);

    // Command array
    const char* cmd[] = { "loadfile", pathUtf8.c_str(), nullptr };
    mpv_command_async(m_mpv, 0, cmd);

    // Seamless software fallback and auto-play
    mpv_command_string(m_mpv, "set pause no");
}

void RenderHost::play()
{
    setPropertyBool("pause", false);
}

void RenderHost::pause()
{
    setPropertyBool("pause", true);
}

void RenderHost::seek(double offset)
{
    std::string offsetStr = std::to_string(offset);
    const char* cmd[] = { "seek", offsetStr.c_str(), "relative+exact", nullptr };
    mpv_command_async(m_mpv, 0, cmd);
}

void RenderHost::setVolume(int volume)
{
    setPropertyInt("volume", volume);
}

void RenderHost::toggleMute()
{
    std::string mute = getPropertyString("mute");
    setProperty("mute", mute == "yes" ? "no" : "yes");
}

void RenderHost::setProperty(const std::string& name, const std::string& value)
{
    if (name == "hwdec") {
        m_hwdecMode = value;
    }
    const char* val = value.c_str();
    mpv_set_property_async(m_mpv, 0, name.c_str(), MPV_FORMAT_STRING, &val);
}

void RenderHost::setPropertyBool(const std::string& name, bool value)
{
    int v = value ? 1 : 0;
    mpv_set_property_async(m_mpv, 0, name.c_str(), MPV_FORMAT_FLAG, &v);
}

void RenderHost::setPropertyInt(const std::string& name, int64_t value)
{
    mpv_set_property_async(m_mpv, 0, name.c_str(), MPV_FORMAT_INT64, &value);
}

void RenderHost::setPropertyDouble(const std::string& name, double value)
{
    mpv_set_property_async(m_mpv, 0, name.c_str(), MPV_FORMAT_DOUBLE, &value);
}

std::string RenderHost::getPropertyString(const std::string& name) const
{
    char* str = mpv_get_property_string(m_mpv, name.c_str());
    if (!str) return "";
    std::string res(str);
    mpv_free(str);
    return res;
}

std::string RenderHost::detectPreferredHwdec() const
{
#if defined(_WIN32)
    return "d3d11va";
#else
    return "auto-safe";
#endif
}

std::string RenderHost::resolveHwdecAfterProbe(const std::string& configuredMode, const std::string& hwdecCurrent, bool isArm64Build)
{
    const std::string current = trim(hwdecCurrent);
    if (!current.empty() && current != "no") {
        return configuredMode;
    }

    if (configuredMode == "d3d11va") {
        return "d3d11va-copy";
    } else if (configuredMode == "d3d11va-copy") {
        if (!isArm64Build) {
            return "dxva2-copy";
        }
        return "no";
    } else if (configuredMode == "dxva2-copy") {
        return "no";
    }
    return "no";
}

void RenderHost::applyHwdecFallbackIfNeeded()
{
    if (m_hwdecFallbackHandled || !m_mpv) {
        return;
    }

    char* hwdecCurrent = mpv_get_property_string(m_mpv, "hwdec-current");
    const std::string current = hwdecCurrent ? trim(hwdecCurrent) : std::string();
    if (hwdecCurrent) {
        mpv_free(hwdecCurrent);
    }

    if (current.empty() || current == "no") {
        m_hwdecMode = resolveHwdecAfterProbe(
            m_hwdecMode,
            current,
#if defined(_M_ARM64) || defined(__aarch64__)
            true
#else
            false
#endif
        );
        mpv_set_property_string(m_mpv, "hwdec", m_hwdecMode.c_str());
    }

    m_hwdecFallbackHandled = true;
}
