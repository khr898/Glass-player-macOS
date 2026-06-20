#pragma once

#include <QWidget>
#include <mpv/client.h>
#include <QString>

class MpvWidget : public QWidget
{
    Q_OBJECT
public:
    explicit MpvWidget(QWidget *parent = nullptr);
    ~MpvWidget();

    void command(const QVariantList &args);
    void setProperty(const QString &name, const QVariant &value);
    void setProperty(const char *name, const QVariant &value);
    QVariant getProperty(const QString &name) const;
    QVariant getProperty(const char *name) const;

    void loadFile(const QString &file);
    void play();
    void pause();
    void seek(double offset);
    void setVolume(int volume);
    void toggleMute();
    static QString resolveHwdecAfterProbe(const QString& configuredMode, const QString& hwdecCurrent, bool isArm64Build);

    // mpv object for more advanced configurations if needed outside
    mpv_handle *mpv() const { return m_mpv; }

signals:
    void positionChanged(double position);
    void durationChanged(double duration);
    void eofReached();
    void pauseChanged(bool paused);
    void fileLoaded();
    void startFile();    // Emitted when mpv begins loading a new file
    void playbackError(const QString &message);
    void playbackRestarted();

protected:
    QPaintEngine *paintEngine() const override { return nullptr; }

private slots:
    void onMpvEvents();

private:
    static void onMpvEventsWrapper(void *ctx);

    void handleEvent(mpv_event *event);
    QString detectPreferredHwdec() const;
    void applyHwdecFallbackIfNeeded();

    mpv_handle *m_mpv;
    QString m_hwdecMode;
    bool m_hwdecFallbackHandled = false;

    bool m_glInitialized = false;
    QString m_pendingFileToLoad;
    QString m_pendingShaders;

    QMetaObject::Connection m_eventConnection;
};
