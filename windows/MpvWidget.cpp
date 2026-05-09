#include "MpvWidget.h"
#include <QCoreApplication>
#include <QDebug>
#include <QOpenGLContext>

MpvWidget::MpvWidget(QWidget *parent)
    : QOpenGLWidget(parent), m_mpv(nullptr), m_mpv_gl(nullptr)
{
    m_mpv = mpv_create();
    if (!m_mpv) {
        qFatal("Could not create mpv context");
    }

    // Setting options
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    // Hardware decoding: use auto-safe so GLSL shaders (Anime4K) are never blocked.
    // hwdec=auto-safe lets mpv fall back to software copy when a shader pipeline is active.
    mpv_set_option_string(m_mpv, "hwdec", "auto-safe");
    // Do NOT force gpu-context here — let mpv pick the correct one for the platform
    // (on Windows this is typically d3d11 or opengl via ANGLE)
    mpv_set_option_string(m_mpv, "gpu-api", "opengl");  // required for GLSL shader support

    if (mpv_initialize(m_mpv) < 0) {
        qFatal("Could not initialize mpv context");
    }

    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);

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
}

void MpvWidget::paintGL()
{
    if (!m_mpv_gl) return;

    mpv_opengl_fbo mpfbo{
        static_cast<int>(defaultFramebufferObject()),
        width(),
        height(),
        0
    };

    int flip_y = 0;

    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_INVALID, nullptr}
    };

    mpv_render_context_render(m_mpv_gl, params);
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
        }
        break;
    }
    case MPV_EVENT_END_FILE:
        emit eofReached();
        break;
    default:
        break;
    }
}

void MpvWidget::command(const QVariantList &args)
{
    QByteArray* strArr = new QByteArray[args.count()];
    const char **cmd = new const char *[args.count() + 1];

    for (int i = 0; i < args.count(); ++i) {
        strArr[i] = args[i].toString().toUtf8();
        cmd[i] = strArr[i].constData();
    }
    cmd[args.count()] = nullptr;

    mpv_command(m_mpv, cmd);

    delete[] cmd;
    delete[] strArr;
}

void MpvWidget::setProperty(const QString &name, const QVariant &value)
{
    if (value.typeId() == QMetaType::Int) {
        int v = value.toInt();
        mpv_set_property(m_mpv, name.toUtf8().constData(), MPV_FORMAT_INT64, &v);
    } else if (value.typeId() == QMetaType::Double) {
        double v = value.toDouble();
        mpv_set_property(m_mpv, name.toUtf8().constData(), MPV_FORMAT_DOUBLE, &v);
    } else {
        mpv_set_property_string(m_mpv, name.toUtf8().constData(), value.toString().toUtf8().constData());
    }
}

QVariant MpvWidget::getProperty(const QString &name) const
{
    char *str = mpv_get_property_string(m_mpv, name.toUtf8().constData());
    if (!str) return QVariant();
    QVariant res(QString::fromUtf8(str));
    mpv_free(str);
    return res;
}

void MpvWidget::loadFile(const QString &file)
{
    command(QVariantList() << "loadfile" << file);
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
    command(QVariantList() << "seek" << QString::number(offset) << "relative");
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
