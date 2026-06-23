#pragma once

#include <unknwn.h>
#include <windows.h>
#undef GetCurrentTime
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <mpv/client.h>
#include <mpv/render_gl.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <string>
#include <functional>
#include <memory>

class RenderHost : public std::enable_shared_from_this<RenderHost>
{
public:
    RenderHost(winrt::Microsoft::UI::Xaml::Controls::SwapChainPanel const& panel);
    ~RenderHost();

    void InitGL();
    void RenderFrame();
    void OnPanelSizeChanged();
    void Shutdown();

    void loadFile(const std::wstring& filePath);
    void play();
    void pause();
    void seek(double offset);
    void setVolume(int volume);
    void toggleMute();

    void setProperty(const std::string& name, const std::string& value);
    void setPropertyBool(const std::string& name, bool value);
    void setPropertyInt(const std::string& name, int64_t value);
    void setPropertyDouble(const std::string& name, double value);
    std::string getPropertyString(const std::string& name) const;

    mpv_handle* mpv() const { return m_mpv; }

    // Callbacks
    void setOnPositionChanged(std::function<void(double)> cb) { m_onPositionChanged = cb; }
    void setOnDurationChanged(std::function<void(double)> cb) { m_onDurationChanged = cb; }
    void setOnEofReached(std::function<void()> cb) { m_onEofReached = cb; }
    void setOnPauseChanged(std::function<void(bool)> cb) { m_onPauseChanged = cb; }
    void setOnFileLoaded(std::function<void()> cb) { m_onFileLoaded = cb; }
    void setOnStartFile(std::function<void()> cb) { m_onStartFile = cb; }
    void setOnPlaybackError(std::function<void(const std::wstring&)> cb) { m_onPlaybackError = cb; }
    void setOnPlaybackRestarted(std::function<void()> cb) { m_onPlaybackRestarted = cb; }

private:
    static void onMpvEventsWrapper(void* ctx);
    static void onUpdateWrapper(void* ctx);

    void PumpEvents();
    void handleEvent(mpv_event* event);
    std::string detectPreferredHwdec() const;
    void applyHwdecFallbackIfNeeded();
    static std::string resolveHwdecAfterProbe(const std::string& configuredMode, const std::string& hwdecCurrent, bool isArm64Build);

    winrt::Microsoft::UI::Xaml::Controls::SwapChainPanel m_panel{ nullptr };
    winrt::Microsoft::UI::Dispatching::DispatcherQueue m_dispatcher{ nullptr };

    EGLDisplay m_eglDisplay{ EGL_NO_DISPLAY };
    EGLConfig m_cfg{ nullptr };
    EGLContext m_eglCtx{ EGL_NO_CONTEXT };
    EGLSurface m_eglSurf{ EGL_NO_SURFACE };

    mpv_handle* m_mpv{ nullptr };
    mpv_render_context* m_mpv_gl{ nullptr };
    std::string m_hwdecMode;
    bool m_hwdecFallbackHandled{ false };
    bool m_glInitialized{ false };
    std::wstring m_pendingFileToLoad;

    // Callbacks
    std::function<void(double)> m_onPositionChanged;
    std::function<void(double)> m_onDurationChanged;
    std::function<void()> m_onEofReached;
    std::function<void(bool)> m_onPauseChanged;
    std::function<void()> m_onFileLoaded;
    std::function<void()> m_onStartFile;
    std::function<void(const std::wstring&)> m_onPlaybackError;
    std::function<void()> m_onPlaybackRestarted;
};
