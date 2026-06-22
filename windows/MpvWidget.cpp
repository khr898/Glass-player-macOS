#include "MpvWidget.h"
#include <QCoreApplication>
#include <QDebug>
#include <QOpenGLContext>
#include <cstdint>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <d3d11.h>
#endif

#include <QDir>

MpvWidget::MpvWidget(QWidget *parent)
    : QOpenGLWidget(parent), m_mpv(nullptr), m_mpv_gl(nullptr)
{
    m_mpv = mpv_create();
    if (!m_mpv) {
        qFatal("Could not create mpv context");
    }

    // Setting options
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    m_hwdecMode = detectPreferredHwdec();
    mpv_set_option_string(m_mpv, "hwdec", m_hwdecMode.toUtf8().constData());
    // Seamless software fallback for unsupported codecs/devices.
    mpv_set_option_string(m_mpv, "hwdec-software-fallback", "yes");
    mpv_set_option_string(m_mpv, "hwdec-codecs", "all");

    // Enforce gpu-api=opengl to ensure correct context rendering and GLSL shader (Anime4K) support
    mpv_set_option_string(m_mpv, "gpu-api", "opengl");
    mpv_set_option_string(m_mpv, "video-sync", "display-resample");
    mpv_set_option_string(m_mpv, "interpolation", "yes");

    // Playback and OSC configurations matching macOS port
    mpv_set_option_string(m_mpv, "keep-open", "yes");
    mpv_set_option_string(m_mpv, "input-default-bindings", "yes");
    mpv_set_option_string(m_mpv, "input-vo-keyboard", "no");
    mpv_set_option_string(m_mpv, "osc", "no");
    mpv_set_option_string(m_mpv, "osd-level", "0");
    mpv_set_option_string(m_mpv, "idle", "yes");
    mpv_set_option_string(m_mpv, "force-window", "no");
    mpv_set_option_string(m_mpv, "volume-max", "200");

    // HDR, Wide Color Gamut & Dolby Vision tone mapping options
    mpv_set_option_string(m_mpv, "target-colorspace-hint", "yes");
    mpv_set_option_string(m_mpv, "hdr-compute-peak", "yes");
    mpv_set_option_string(m_mpv, "tone-mapping", "bt.2390");

    // Dolby Atmos, DTS-HD, TrueHD, 5.1 & 7.1 multi-channel audio setups
    mpv_set_option_string(m_mpv, "ao", "wasapi");
    mpv_set_option_string(m_mpv, "audio-channels", "auto");
    mpv_set_option_string(m_mpv, "audio-spdif", "");

    if (mpv_initialize(m_mpv) < 0) {
        qFatal("Could not initialize mpv context");
    }

    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "track-list/count", MPV_FORMAT_INT64);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);

    mpv_set_wakeup_callback(m_mpv, onMpvEventsWrapper, this);
}

MpvWidget::~MpvWidget()
{
    makeCurrent();
    if (m_mpv_gl) {
        mpv_render_context_free(m_mpv_gl);
    }
    if (m_mpv) {
        mpv_terminate_destroy(m_mpv);
    }
    doneCurrent();
}

static void *get_proc_address(void *ctx, const char *name) {
    Q_UNUSED(ctx);
    QOpenGLContext *glctx = QOpenGLContext::currentContext();
    if (!glctx)
        return nullptr;
    return reinterpret_cast<void *>(glctx->getProcAddress(QByteArray(name)));
}

void MpvWidget::initializeGL()
{
    initializeOpenGLFunctions();

    if (m_mpv_gl) {
        mpv_render_context_free(m_mpv_gl);
        m_mpv_gl = nullptr;
    }

    mpv_opengl_init_params gl_init_params{get_proc_address, nullptr};
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init_params},
        {MPV_RENDER_PARAM_INVALID, nullptr}
    };

    if (mpv_render_context_create(&m_mpv_gl, m_mpv, params) < 0) {
        qFatal("Failed to initialize mpv GL context");
    }

    mpv_render_context_set_update_callback(m_mpv_gl, onUpdateWrapper, this);

    m_glInitialized = true;
    if (!m_pendingFileToLoad.isEmpty()) {
        QString file = m_pendingFileToLoad;
        m_pendingFileToLoad.clear();
        loadFile(file);
    }
}

void MpvWidget::paintGL()
{
    if (!m_mpv_gl) return;

    const int w = width() * devicePixelRatio();
    const int h = height() * devicePixelRatio();

    // Ensure OpenGL viewport is set to the physical dimensions to fix High-DPI corner scaling
    glViewport(0, 0, w, h);

    mpv_opengl_fbo mpfbo{
        static_cast<int>(defaultFramebufferObject()),
        w,
        h,
        0
    };

    int flip_y = 1; // Fix upside-down video playback by flipping Y axis to align with Qt

    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_INVALID, nullptr}
    };

    mpv_render_context_render(m_mpv_gl, params);
    mpv_render_context_report_swap(m_mpv_gl);
}

void MpvWidget::resizeGL(int w, int h)
{
    Q_UNUSED(w);
    Q_UNUSED(h);
    // mpv handles resize naturally on next render with updated width/height
}

void MpvWidget::onMpvEventsWrapper(void *ctx)
{
    QMetaObject::invokeMethod(static_cast<MpvWidget*>(ctx), "onMpvEvents", Qt::QueuedConnection);
}

void MpvWidget::onUpdateWrapper(void *ctx)
{
    QMetaObject::invokeMethod(static_cast<MpvWidget*>(ctx), "doUpdate", Qt::QueuedConnection);
}

void MpvWidget::doUpdate()
{
    update();
}

void MpvWidget::onMpvEvents()
{
    while (m_mpv) {
        mpv_event *event = mpv_wait_event(m_mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;
        handleEvent(event);
    }
}

void MpvWidget::handleEvent(mpv_event *event)
{
    switch (event->event_id) {
    case MPV_EVENT_START_FILE:
        m_hwdecFallbackHandled = false;
        mpv_set_property_string(m_mpv, "hwdec", m_hwdecMode.toUtf8().constData());
        emit startFile();
        break;
    case MPV_EVENT_FILE_LOADED:
        applyHwdecFallbackIfNeeded();
        emit fileLoaded();
        break;
    case MPV_EVENT_PROPERTY_CHANGE: {
        mpv_event_property *prop = static_cast<mpv_event_property *>(event->data);
        if (qstrcmp(prop->name, "time-pos") == 0) {
            if (prop->format == MPV_FORMAT_DOUBLE) {
                emit positionChanged(*(double *)prop->data);
            }
        } else if (qstrcmp(prop->name, "duration") == 0) {
            if (prop->format == MPV_FORMAT_DOUBLE) {
                emit durationChanged(*(double *)prop->data);
            }
        } else if (qstrcmp(prop->name, "pause") == 0) {
            if (prop->format == MPV_FORMAT_FLAG) {
                emit pauseChanged(*(int *)prop->data != 0);
            }
        }
        break;
    }
    case MPV_EVENT_END_FILE: {
        mpv_event_end_file *eof = static_cast<mpv_event_end_file*>(event->data);
        if (eof && eof->reason == MPV_END_FILE_REASON_ERROR) {
            emit playbackError(QString::fromUtf8(mpv_error_string(eof->error)));
        } else {
            emit eofReached();
        }
        break;
    }
    case MPV_EVENT_PLAYBACK_RESTART:
        emit playbackRestarted();
        break;
    default:
        break;
    }
}

void MpvWidget::command(const QVariantList &args)
{
    const int n = args.count();
    std::vector<QByteArray> strArr(n);
    std::vector<const char*> cmd(n + 1);
    for (int i = 0; i < n; ++i) {
        strArr[i] = args[i].toString().toUtf8();
        cmd[i] = strArr[i].constData();
    }
    cmd[n] = nullptr;
    int err = mpv_command(m_mpv, cmd.data());
    if (err < 0) {
        qWarning() << "[MpvWidget] mpv_command failed:" << mpv_error_string(err) << "for args:" << args;
    }
}

void MpvWidget::setProperty(const char *name, const QVariant &value)
{
    if (strcmp(name, "hwdec") == 0) {
        m_hwdecMode = value.toString();
    }

    if (value.typeId() == QMetaType::Bool) {
        int v = value.toBool() ? 1 : 0;
        mpv_set_property(m_mpv, name, MPV_FORMAT_FLAG, &v);
    } else if (value.typeId() == QMetaType::Int) {
        int64_t v = static_cast<int64_t>(value.toInt());
        mpv_set_property(m_mpv, name, MPV_FORMAT_INT64, &v);
    } else if (value.typeId() == QMetaType::Double) {
        double v = value.toDouble();
        mpv_set_property(m_mpv, name, MPV_FORMAT_DOUBLE, &v);
    } else {
        mpv_set_property_string(m_mpv, name, value.toString().toUtf8().constData());
    }
}

void MpvWidget::setProperty(const QString &name, const QVariant &value)
{
    setProperty(name.toUtf8().constData(), value);
}

QVariant MpvWidget::getProperty(const char *name) const
{
    char *str = mpv_get_property_string(m_mpv, name);
    if (!str) return QVariant();
    QVariant res(QString::fromUtf8(str));
    mpv_free(str);
    return res;
}

QVariant MpvWidget::getProperty(const QString &name) const
{
    return getProperty(name.toUtf8().constData());
}

void MpvWidget::loadFile(const QString &file)
{
    if (!m_glInitialized) {
        m_pendingFileToLoad = file;
        return;
    }

    // Avoid applying QDir::toNativeSeparators to streaming URLs to prevent corruption of forward slashes
    if (file.contains("://")) {
        command(QVariantList() << "loadfile" << file);
    } else {
        command(QVariantList() << "loadfile" << QDir::toNativeSeparators(file));
    }

    // Ensure playback starts immediately.
    // Some containers (TS, VOB, MKV with certain codecs) leave mpv in a
    // paused state after loadfile when keep-open=yes is set.
    // Sending 'set pause no' here guarantees auto-play without the user
    // needing to scrub first.
    mpv_command_string(m_mpv, "set pause no");
}

void MpvWidget::play()
{
    setProperty("pause", false);
}

void MpvWidget::pause()
{
    setProperty("pause", true);
}

void MpvWidget::seek(double offset)
{
    command(QVariantList() << "seek" << QString::number(offset) << "relative+exact");
}

void MpvWidget::setVolume(int volume)
{
    setProperty("volume", volume);
}

void MpvWidget::toggleMute()
{
    QString mute = getProperty("mute").toString();
    setProperty("mute", mute == "yes" ? "no" : "yes");
}

QString MpvWidget::detectPreferredHwdec() const
{
#ifdef _WIN32
    // On Windows, d3d11va-copy is highly compatible and supports GLSL shader scaling.
    // Probing via D3D11CreateDevice is removed as it causes significant startup lag.
    return "d3d11va-copy";
#else
    return "auto-safe";
#endif
}

QString MpvWidget::resolveHwdecAfterProbe(const QString& configuredMode, const QString& hwdecCurrent, bool isArm64Build)
{
    const QString current = hwdecCurrent.trimmed();
    if (!current.isEmpty() && current != "no") {
        return configuredMode;
    }

    if (!isArm64Build && configuredMode == "d3d11va-copy") {
        return "dxva2-copy";
    }
    return "no";
}

void MpvWidget::applyHwdecFallbackIfNeeded()
{
    if (m_hwdecFallbackHandled || !m_mpv) {
        return;
    }

    char* hwdecCurrent = mpv_get_property_string(m_mpv, "hwdec-current");
    const QString current = hwdecCurrent ? QString::fromUtf8(hwdecCurrent).trimmed() : QString();
    if (hwdecCurrent) {
        mpv_free(hwdecCurrent);
    }

    // If mpv failed to initialize HW decoding for this device/session, downgrade once.
    if (current.isEmpty() || current == "no") {
        m_hwdecMode = resolveHwdecAfterProbe(
            m_hwdecMode,
            current,
#if defined(_M_ARM64) || defined(__aarch64__)
            true
#else
            false
#endif
        );
        mpv_set_property_string(m_mpv, "hwdec", m_hwdecMode.toUtf8().constData());
    }

    m_hwdecFallbackHandled = true;
}
