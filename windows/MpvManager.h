#pragma once

#include <windows.h>
#undef GetCurrentTime
#include <mpv/client.h>
#include <string>
#include <functional>
#include <winrt/Microsoft.UI.Dispatching.h>

class MpvManager
{
public:
    MpvManager();
    ~MpvManager();

    void initialize(HWND videoHwnd);
    void terminate();

    // Player controls
    void loadFile(const std::wstring& filePath);
    void play();
    void pause();
    void seek(double offset, bool absolute = false, bool exact = true);
    void setVolume(int volume);
    void setMute(bool mute);
    void setProperty(const std::string& name, const std::string& value);
    std::string getPropertyString(const std::string& name) const;
    double getPropertyDouble(const std::string& name) const;
    int getPropertyInt(const std::string& name) const;
    bool getPropertyBool(const std::string& name) const;

    // Callbacks
    void setOnPositionChanged(std::function<void(double)> cb) { m_onPositionChanged = cb; }
    void setOnDurationChanged(std::function<void(double)> cb) { m_onDurationChanged = cb; }
    void setOnEofReached(std::function<void()> cb) { m_onEofReached = cb; }
    void setOnPauseChanged(std::function<void(bool)> cb) { m_onPauseChanged = cb; }
    void setOnFileLoaded(std::function<void()> cb) { m_onFileLoaded = cb; }
    void setOnStartFile(std::function<void()> cb) { m_onStartFile = cb; }
    void setOnPlaybackError(std::function<void(const std::wstring&)> cb) { m_onPlaybackError = cb; }

    mpv_handle* handle() const { return m_mpv; }

private:
    void eventLoop();
    std::wstring toWString(const std::string& str);
    std::string toString(const std::wstring& wstr);

    mpv_handle* m_mpv{ nullptr };
    HWND m_videoHwnd{ nullptr };
    winrt::Microsoft::UI::Dispatching::DispatcherQueue m_dispatcherQueue{ nullptr };
    
    // Background event thread
    HANDLE m_eventThread{ nullptr };
    bool m_shutdown{ false };

    // Callbacks
    std::function<void(double)> m_onPositionChanged;
    std::function<void(double)> m_onDurationChanged;
    std::function<void()> m_onEofReached;
    std::function<void(bool)> m_onPauseChanged;
    std::function<void()> m_onFileLoaded;
    std::function<void()> m_onStartFile;
    std::function<void(const std::wstring&)> m_onPlaybackError;
};
