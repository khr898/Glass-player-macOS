#include "MpvManager.h"
#include <thread>
#include <stdexcept>
#include <locale>
#include <codecvt>

MpvManager::MpvManager()
{
}

MpvManager::~MpvManager()
{
    terminate();
}

void MpvManager::initialize(HWND videoHwnd)
{
    m_videoHwnd = videoHwnd;
    m_dispatcherQueue = winrt::Microsoft::UI::Dispatching::DispatcherQueue::GetForCurrentThread();

    m_mpv = mpv_create();
    if (!m_mpv) {
        throw std::runtime_error("Could not create mpv context");
    }

    // Set rendering options for native window rendering
    mpv_set_option_string(m_mpv, "vo", "gpu-next");
    mpv_set_option_string(m_mpv, "gpu-api", "d3d11");
    mpv_set_option_string(m_mpv, "hwdec", "d3d11va");
    mpv_set_option_string(m_mpv, "hwdec-software-fallback", "yes");
    mpv_set_option_string(m_mpv, "hwdec-codecs", "all");
    mpv_set_option_string(m_mpv, "video-sync", "display-resample");
    mpv_set_option_string(m_mpv, "interpolation", "yes");

    // Standard player flags
    mpv_set_option_string(m_mpv, "keep-open", "yes");
    mpv_set_option_string(m_mpv, "input-default-bindings", "yes");
    mpv_set_option_string(m_mpv, "input-vo-keyboard", "no");
    mpv_set_option_string(m_mpv, "osc", "no");
    mpv_set_option_string(m_mpv, "osd-level", "0");
    mpv_set_option_string(m_mpv, "idle", "yes");
    mpv_set_option_string(m_mpv, "force-window", "no");
    mpv_set_option_string(m_mpv, "volume-max", "200");

    // HDR and audio options
    mpv_set_option_string(m_mpv, "target-colorspace-hint", "yes");
    mpv_set_option_string(m_mpv, "hdr-compute-peak", "yes");
    mpv_set_option_string(m_mpv, "tone-mapping", "bt.2390");
    mpv_set_option_string(m_mpv, "ao", "wasapi");
    mpv_set_option_string(m_mpv, "audio-channels", "auto");
    mpv_set_option_string(m_mpv, "audio-spdif", "");

    // Pass the window ID to embed video rendering
    intptr_t wid = reinterpret_cast<intptr_t>(videoHwnd);
    mpv_set_option(m_mpv, "wid", MPV_FORMAT_INT64, &wid);

    if (mpv_initialize(m_mpv) < 0) {
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
        throw std::runtime_error("Could not initialize mpv context");
    }

    // Observe playback properties
    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);

    // Start background event loop thread
    m_shutdown = false;
    m_eventThread = CreateThread(nullptr, 0, [](LPVOID lpParam) -> DWORD {
        static_cast<MpvManager*>(lpParam)->eventLoop();
        return 0;
    }, this, 0, nullptr);
}

void MpvManager::terminate()
{
    m_shutdown = true;
    if (m_eventThread) {
        WaitForSingleObject(m_eventThread, INFINITE);
        CloseHandle(m_eventThread);
        m_eventThread = nullptr;
    }
    if (m_mpv) {
        mpv_terminate_destroy(m_mpv);
        m_mpv = nullptr;
    }
}

void MpvManager::loadFile(const std::wstring& filePath)
{
    if (!m_mpv) return;
    std::string pathStr = toString(filePath);
    const char* cmd[] = { "loadfile", pathStr.c_str(), nullptr };
    mpv_command(m_mpv, cmd);
}

void MpvManager::play()
{
    if (!m_mpv) return;
    int pauseFlag = 0;
    mpv_set_property(m_mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag);
}

void MpvManager::pause()
{
    if (!m_mpv) return;
    int pauseFlag = 1;
    mpv_set_property(m_mpv, "pause", MPV_FORMAT_FLAG, &pauseFlag);
}

void MpvManager::seek(double offset, bool absolute, bool exact)
{
    if (!m_mpv) return;
    std::string offsetStr = std::to_string(offset);
    std::string flags = absolute ? (exact ? "absolute+exact" : "absolute+keyframes") : (exact ? "relative+exact" : "relative+keyframes");
    const char* cmd[] = { "seek", offsetStr.c_str(), flags.c_str(), nullptr };
    mpv_command(m_mpv, cmd);
}

void MpvManager::setVolume(int volume)
{
    if (!m_mpv) return;
    double volDouble = static_cast<double>(volume);
    mpv_set_property(m_mpv, "volume", MPV_FORMAT_DOUBLE, &volDouble);
}

void MpvManager::setMute(bool mute)
{
    if (!m_mpv) return;
    int muteFlag = mute ? 1 : 0;
    mpv_set_property(m_mpv, "mute", MPV_FORMAT_FLAG, &muteFlag);
}

void MpvManager::setProperty(const std::string& name, const std::string& value)
{
    if (!m_mpv) return;
    mpv_set_property_string(m_mpv, name.c_str(), value.c_str());
}

std::string MpvManager::getPropertyString(const std::string& name) const
{
    if (!m_mpv) return "";
    char* val = mpv_get_property_string(m_mpv, name.c_str());
    if (!val) return "";
    std::string res(val);
    mpv_free(val);
    return res;
}

double MpvManager::getPropertyDouble(const std::string& name) const
{
    if (!m_mpv) return 0.0;
    double val = 0.0;
    mpv_get_property(m_mpv, name.c_str(), MPV_FORMAT_DOUBLE, &val);
    return val;
}

int MpvManager::getPropertyInt(const std::string& name) const
{
    if (!m_mpv) return 0;
    int64_t val = 0;
    mpv_get_property(m_mpv, name.c_str(), MPV_FORMAT_INT64, &val);
    return static_cast<int>(val);
}

bool MpvManager::getPropertyBool(const std::string& name) const
{
    if (!m_mpv) return false;
    int val = 0;
    mpv_get_property(m_mpv, name.c_str(), MPV_FORMAT_FLAG, &val);
    return val != 0;
}

void MpvManager::eventLoop()
{
    while (!m_shutdown) {
        mpv_event* event = mpv_wait_event(m_mpv, 0.1);
        if (!event || event->event_id == MPV_EVENT_NONE) {
            continue;
        }

        // Copy event information to send to UI thread
        struct EventData {
            mpv_event_id id;
            int error;
            std::string propName;
            double propDouble = 0.0;
            bool propBool = false;
        } evt;

        evt.id = event->event_id;
        evt.error = event->error;

        if (event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
            mpv_event_property* prop = static_cast<mpv_event_property*>(event->data);
            evt.propName = prop->name;
            if (prop->format == MPV_FORMAT_DOUBLE && prop->data) {
                evt.propDouble = *static_cast<double*>(prop->data);
            } else if (prop->format == MPV_FORMAT_FLAG && prop->data) {
                evt.propBool = *static_cast<int*>(prop->data) != 0;
            }
        }

        // Post work to WinUI 3 UI Thread dispatcher
        if (m_dispatcherQueue && !m_shutdown) {
            m_dispatcherQueue.TryEnqueue([this, evt]() {
                if (m_shutdown) return;
                
                switch (evt.id) {
                    case MPV_EVENT_START_FILE:
                        if (m_onStartFile) m_onStartFile();
                        break;
                    case MPV_EVENT_FILE_LOADED:
                        if (m_onFileLoaded) m_onFileLoaded();
                        break;
                    case MPV_EVENT_END_FILE:
                        if (evt.error < 0) {
                            if (m_onPlaybackError) m_onPlaybackError(L"Playback error occurred.");
                        } else {
                            if (m_onEofReached) m_onEofReached();
                        }
                        break;
                    case MPV_EVENT_PROPERTY_CHANGE:
                        if (evt.propName == "time-pos") {
                            if (m_onPositionChanged) m_onPositionChanged(evt.propDouble);
                        } else if (evt.propName == "duration") {
                            if (m_onDurationChanged) m_onDurationChanged(evt.propDouble);
                        } else if (evt.propName == "pause") {
                            if (m_onPauseChanged) m_onPauseChanged(evt.propBool);
                        }
                        break;
                    default:
                        break;
                }
            });
        }
    }
}

std::wstring MpvManager::toWString(const std::string& str)
{
    if (str.empty()) return L"";
    std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
    return converter.from_bytes(str);
}

std::string MpvManager::toString(const std::wstring& wstr)
{
    if (wstr.empty()) return "";
    std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
    return converter.to_bytes(wstr);
}
