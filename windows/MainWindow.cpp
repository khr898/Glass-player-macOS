#include "MainWindow.h"

#include "Theme.h"
#include "WinOSIntegration.h"
#include <QApplication>
#include <QFileDialog>
#include <QKeyEvent>
#include <QFile>
#include <QTemporaryDir>
#include <QStandardPaths>
#include <QTimer>
#include <QCursor>
#include <QHash>
#include <QSignalBlocker>
#include <QMenu>
#include <QAction>
#include <QDir>
#include <QWheelEvent>
#include <QGraphicsDropShadowEffect>
#include <QShortcut>
#include <QGuiApplication>
#include <QFileInfo>
#include <QMessageBox>
#include <QStyleHints>
#include <QScreen>
#include <algorithm>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <functional>
#include <QDateTime>
#include <QThread>
#include <QImage>
#include <QCoreApplication>

class TimelinePreviewWidget : public QWidget {
public:
    explicit TimelinePreviewWidget(QWidget *parent = nullptr) : QWidget(parent) {
        setFixedSize(180, 120);
        
        // Semi-transparent dark background with rounded corners matching premium visual effect
        setStyleSheet(
            QString(
                "QWidget { "
                "  background-color: %1; "
                "  border: 1px solid %2; "
                "  border-radius: 8px; "
                "}"
            ).arg(Theme::kBgSurface, Theme::kBorderElevated)
        );

        m_imgLabel = new QLabel(this);
        m_imgLabel->setGeometry(4, 4, 172, 94); // fit beautifully inside
        m_imgLabel->setStyleSheet("background-color: rgba(0, 0, 0, 120); border-radius: 4px; border: none;");
        m_imgLabel->setScaledContents(true);

        m_timeLabel = new QLabel(this);
        m_timeLabel->setGeometry(0, 100, 180, 18);
        m_timeLabel->setAlignment(Qt::AlignCenter);
        m_timeLabel->setStyleSheet(
            QString(
                "color: %1; font-family: %2; font-size: 11px; font-weight: bold; background: transparent; border: none;"
            ).arg(Theme::kTextPrimary, Theme::kFontMono)
        );
        
        hide();
    }

    void setPreview(const QImage &img, const QString &timeStr, bool keepPrevious = false) {
        if (!img.isNull()) {
            m_imgLabel->setPixmap(QPixmap::fromImage(img));
        } else if (!keepPrevious) {
            m_imgLabel->clear();
        }
        m_timeLabel->setText(timeStr);
    }

private:
    QLabel *m_imgLabel;
    QLabel *m_timeLabel;
};

class ThumbnailMpv {
public:
    explicit ThumbnailMpv(void *instanceId = nullptr) {
        m_tmpPath = QDir::tempPath() + QString("/glassplayer_thumb_%1_%2.jpg")
            .arg(QCoreApplication::applicationPid())
            .arg(reinterpret_cast<quintptr>(instanceId), 0, 16);
        m_workerThread = std::thread(&ThumbnailMpv::workerLoop, this);
    }
    ~ThumbnailMpv() {
        shutdown();
    }

    void shutdown() {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_shutdown = true;
        }
        m_cv.notify_all();
        if (m_workerThread.joinable()) {
            m_workerThread.join();
        }
        if (m_mpv) {
            mpv_terminate_destroy(m_mpv);
            m_mpv = nullptr;
        }
        QFile::remove(m_tmpPath);
        m_currentFile.clear();
    }

    void loadSource(const QString &source) {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_pendingSource = source;
            m_hasPendingSource = true;
        }
        m_cv.notify_all();
    }

    struct ThumbnailRequest {
        double time = 0.0;
        int cacheKey = 0;
        QObject *context = nullptr;
        std::function<void(QImage, int)> callback;
    };

    void requestThumbnail(double time, int cacheKey, QObject *context, std::function<void(QImage, int)> callback) {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_pendingThumbnail = { time, cacheKey, context, callback };
            m_hasPendingThumbnail = true;
        }
        m_cv.notify_all();
    }

private:
    void workerLoop() {
        setupMpv();
        if (!m_mpv) return;

        while (true) {
            QString src;
            bool doLoad = false;
            ThumbnailRequest req;
            bool doThumb = false;

            {
                std::unique_lock<std::mutex> lock(m_mutex);
                m_cv.wait(lock, [this]() {
                    return m_shutdown || m_hasPendingSource || m_hasPendingThumbnail;
                });

                if (m_shutdown) {
                    break;
                }

                if (m_hasPendingSource) {
                    src = m_pendingSource;
                    m_hasPendingSource = false;
                    doLoad = true;
                } else if (m_hasPendingThumbnail) {
                    req = m_pendingThumbnail;
                    m_hasPendingThumbnail = false;
                    doThumb = true;
                }
            }

            if (doLoad) {
                performLoadSource(src);
            } else if (doThumb) {
                performGenerateThumbnail(req);
            }
        }

        if (m_mpv) {
            mpv_terminate_destroy(m_mpv);
            m_mpv = nullptr;
        }
    }

    void performLoadSource(const QString &source) {
        if (!m_mpv) return;
        if (source == m_currentFile) return;
        m_currentFile = source;

        mpv_command_string(m_mpv, "set pause yes");
        
        QByteArray srcBytes = source.toUtf8();
        if (source.contains("://")) {
            const char *cmd[] = {"loadfile", srcBytes.constData(), "replace", nullptr};
            mpv_command(m_mpv, cmd);
        } else {
            QByteArray nativePath = QDir::toNativeSeparators(source).toUtf8();
            const char *cmd[] = {"loadfile", nativePath.constData(), "replace", nullptr};
            mpv_command(m_mpv, cmd);
        }

        for (int i = 0; i < 40; ++i) {
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                if (m_shutdown) return;
            }
            mpv_event *event = mpv_wait_event(m_mpv, 0.05);
            if (!event || event->event_id == MPV_EVENT_NONE) continue;
            if (event->event_id == MPV_EVENT_FILE_LOADED) break;
        }
    }

    void performGenerateThumbnail(const ThumbnailRequest &req) {
        if (!m_mpv) return;

        QString seekCmd = QString("seek %1 absolute+exact").arg(req.time, 0, 'f', 6);
        mpv_command_string(m_mpv, seekCmd.toUtf8().constData());

        for (int i = 0; i < 15; ++i) {
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                if (m_shutdown) return;
            }
            mpv_event *event = mpv_wait_event(m_mpv, 0.002);
            if (!event || event->event_id == MPV_EVENT_NONE) break;
            if (event->event_id == MPV_EVENT_PLAYBACK_RESTART) break;
        }

        QByteArray tmpPathBytes = QDir::toNativeSeparators(m_tmpPath).toUtf8();
        const char *screenshotCmd[] = {"screenshot-to-file", tmpPathBytes.constData(), "video", nullptr};
        mpv_command(m_mpv, screenshotCmd);

        QImage result;
        for (int attempt = 0; attempt < 4; ++attempt) {
            {
                std::lock_guard<std::mutex> lock(m_mutex);
                if (m_shutdown) return;
            }
            if (QFile::exists(m_tmpPath)) {
                QImage img(m_tmpPath);
                if (!img.isNull()) {
                    result = img.scaled(240, 135, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                    break;
                }
            }
            if (attempt < 3) {
                QThread::msleep(3);
            }
        }
        QFile::remove(m_tmpPath);

        if (req.context && req.callback) {
            QMetaObject::invokeMethod(req.context, [callback = req.callback, result, key = req.cacheKey]() {
                callback(result, key);
            }, Qt::QueuedConnection);
        }
    }

    void setupMpv() {
        m_mpv = mpv_create();
        if (!m_mpv) return;

        mpv_set_option_string(m_mpv, "vo", "null");
        mpv_set_option_string(m_mpv, "ao", "null");
        mpv_set_option_string(m_mpv, "aid", "no");
        mpv_set_option_string(m_mpv, "sid", "no");
        mpv_set_option_string(m_mpv, "hwdec", "d3d11va-copy");
        mpv_set_option_string(m_mpv, "keep-open", "yes");
        mpv_set_option_string(m_mpv, "idle", "yes");
        mpv_set_option_string(m_mpv, "osc", "no");
        mpv_set_option_string(m_mpv, "osd-level", "0");
        mpv_set_option_string(m_mpv, "terminal", "no");
        mpv_set_option_string(m_mpv, "msg-level", "all=no");
        mpv_set_option_string(m_mpv, "vd-lavc-threads", "4");
        mpv_set_option_string(m_mpv, "hr-seek-framedrop", "yes");
        mpv_set_option_string(m_mpv, "demuxer-max-bytes", "5MiB");
        mpv_set_option_string(m_mpv, "demuxer-max-back-bytes", "1MiB");
        mpv_set_option_string(m_mpv, "screenshot-format", "jpg");
        mpv_set_option_string(m_mpv, "screenshot-jpeg-quality", "30");

        if (mpv_initialize(m_mpv) < 0) {
            mpv_destroy(m_mpv);
            m_mpv = nullptr;
        }
    }

    mpv_handle *m_mpv = nullptr;
    QString m_tmpPath;
    QString m_currentFile;

    std::thread m_workerThread;
    std::mutex m_mutex;
    std::condition_variable m_cv;
    bool m_shutdown = false;

    QString m_pendingSource;
    bool m_hasPendingSource = false;

    ThumbnailRequest m_pendingThumbnail;
    bool m_hasPendingThumbnail = false;
};


int MainWindow::s_windowCount = 0;
static const QString kMenuStyle = Theme::kMenuStyle;

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent), m_settings("GlassPlayer", "Settings")
{
    s_windowCount++;
    setupUi();

    m_seekTimeoutTimer = new QTimer(this);
    m_seekTimeoutTimer->setSingleShot(true);
    m_seekTimeoutTimer->setInterval(3000);
    connect(m_seekTimeoutTimer, &QTimer::timeout, this, [this]() {
        if (m_seekInProgress) {
            qDebug() << "[MainWindow] Seek timeout - forcing unstick";
            m_seekInProgress = false;
            m_seekCommandPending = false;
            m_isSeeking = false;
            m_mpvWidget->command(QVariantList() << "set" << "pause" << "no");
        }
    });

    connect(m_mpvWidget, &MpvWidget::positionChanged, this, &MainWindow::updatePosition);
    connect(m_mpvWidget, &MpvWidget::durationChanged, this, &MainWindow::updateDuration);
    connect(m_mpvWidget, &MpvWidget::fileLoaded, this, &MainWindow::onFileLoaded);
    connect(m_mpvWidget, &MpvWidget::startFile, this, &MainWindow::onStartFile);
    connect(m_brightnessSlider, &QSlider::sliderReleased, this, &MainWindow::updateHoverBars);
    connect(m_volumeHoverSlider, &QSlider::sliderReleased, this, &MainWindow::updateHoverBars);
    connect(m_mpvWidget, &MpvWidget::playbackError, this, [this](const QString &msg) {
        qWarning() << "[MainWindow] Playback error:" << msg;
        if (m_titleLabel) {
            m_titleLabel->setText(QString("Error: %1").arg(msg));
        }
    });
    connect(m_mpvWidget, &MpvWidget::playbackRestarted, this, [this]() {
        m_seekTimeoutTimer->stop();
        if (m_seekCommandPending) {
            m_seekCommandPending = false;
            qDebug() << "[MainWindow] Executing deferred seek to" << m_queuedSeekTarget;
            m_seekInProgress = true;
            m_seekTimeoutTimer->start();
            m_mpvWidget->command(QVariantList() << "seek" << QString::number(m_queuedSeekTarget, 'f', 6) << "absolute+exact");
        } else {
            m_seekInProgress = false;
            m_isSeeking = false;
        }
    });
    connect(m_mpvWidget, &MpvWidget::pauseChanged, this, [this](bool paused) {
        m_isPlaying = !paused;
        m_playPauseBtn->setIcon(QIcon(paused ? ":/icons/play.svg" : ":/icons/pause.svg"));
        if (!paused) {
            hideHud();
            // Reset watchdog baseline so a fresh file doesn't trigger immediately
            m_lastPositionTime = QDateTime::currentMSecsSinceEpoch();
            m_systemSyncTimer->start();
            m_stallWatchdog->start();
        } else {
            showHud();
            syncSystemControls(); // final sync
            m_systemSyncTimer->stop();
            m_stallWatchdog->stop();
        }
    });
    
    const int initialSystemVolume = qRound(WinOSIntegration::instance().getSystemVolume() * 100.0f);
    m_volumeSlider->setValue(initialSystemVolume);
    syncSystemControls();
    
    connect(m_mpvWidget, &MpvWidget::eofReached, this, [this](){
        m_isPlaying = false;
        m_playPauseBtn->setIcon(QIcon(":/icons/play.svg"));
        m_systemSyncTimer->stop();
        m_stallWatchdog->stop();
    });

    m_welcomeWindow = new WelcomeWindow(this);
    connect(m_welcomeWindow, &WelcomeWindow::fileOpened, this, &MainWindow::openFile);
    connect(m_welcomeWindow, &WelcomeWindow::openRcloneBrowser, this, &MainWindow::onRcloneClicked);

    m_settingsWindow = new SettingsWindow(this);
    m_settingsWindow->setWindowModality(Qt::ApplicationModal);
    m_settingsWindow->setWindowFlags(Qt::Dialog | Qt::WindowStaysOnTopHint);
    connect(m_settingsWindow, &SettingsWindow::settingChanged, this, &MainWindow::applySettingToMpv);

    m_hudTimer = new QTimer(this);
    m_hudTimer->setSingleShot(true);
    connect(m_hudTimer, &QTimer::timeout, this, &MainWindow::hideHud);
    m_hudTimer->start(3000);

    m_clickTimer = new QTimer(this);
    m_clickTimer->setSingleShot(true);
    m_clickTimer->setInterval(200);
    connect(m_clickTimer, &QTimer::timeout, this, [this]() {
        if (m_bottomBar->isVisible()) {
            hideHud();
        } else {
            showHud();
        }
    });

    // Bi-directional OS sync: keep sliders/icons in sync when values change externally.
    m_systemSyncTimer = new QTimer(this);
    m_systemSyncTimer->setInterval(250);
    connect(m_systemSyncTimer, &QTimer::timeout, this, &MainWindow::syncSystemControls);
    // Do not auto-start m_systemSyncTimer here

    // Stall watchdog: if playback is active but no position updates arrive for
    // > 5 s, nudge mpv with a zero-delta seek to unblock stuck demuxer/decoder.
    m_stallWatchdog = new QTimer(this);
    m_stallWatchdog->setInterval(5000);
    connect(m_stallWatchdog, &QTimer::timeout, this, [this]() {
        if (!m_isPlaying || m_isSeeking || m_duration <= 0) return;
        // Only for network streams
        if (!m_currentFile.contains("://")) return;
        qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - m_lastPositionTime;
        if (elapsed > 8000) {
            // Verify cache is depleted
            double cacheTime = m_mpvWidget->getProperty("demuxer-cache-time").toDouble();
            if (cacheTime < 1.0) {
                qDebug() << "[MainWindow] Stall watchdog: nudging mpv (stream, cache=" << cacheTime << "s)";
                m_mpvWidget->command(QVariantList() << "seek" << 0 << "relative+exact");
                m_lastPositionTime = QDateTime::currentMSecsSinceEpoch();
            }
        }
    });
    // Do not auto-start m_stallWatchdog here

    setMouseTracking(true);
    centralWidget()->setMouseTracking(true);
    m_mpvWidget->setMouseTracking(true);
    m_mpvWidget->installEventFilter(this);
    m_rcloneBrowser = new RcloneBrowser(this);
    m_rcloneBrowser->setWindowModality(Qt::ApplicationModal);
    m_rcloneBrowser->setWindowFlags(Qt::Dialog | Qt::WindowStaysOnTopHint);
    connect(m_rcloneBrowser, &RcloneBrowser::fileSelected, this, &MainWindow::openFile);

    // Initialize default settings if first run
    if (!m_settings.contains("showWelcome")) {
        m_settings.setValue("showWelcome", true);
        m_settings.setValue("resumePlayback", true);
        m_settings.setValue("hwdec", "auto-safe");
        m_settings.setValue("defaultShaderPreset", "Off");
        m_settings.setValue("volumeMax", "200%");
        m_settings.setValue("audioOutput", "wasapi");
        m_settings.setValue("audioChannels", "auto");
        m_settings.setValue("subAutoLoad", true);
        m_settings.setValue("subFontSize", "36");
        m_settings.setValue("cacheEnabled", true);
        m_settings.setValue("cacheSecs", "120");
        m_settings.setValue("videoProfile", "high-quality");
        m_settings.setValue("scaleFilter", "ewa_lanczossharp");
        m_settings.setValue("dscaleFilter", "mitchell");
        m_settings.setValue("toneMapping", "spline");
        m_settings.setValue("hdrComputePeak", true);
    }

    if (m_settings.value("defaultShaderPreset").toString() == "Auto " "(Recommended)") {
        m_settings.setValue("defaultShaderPreset", "Off");
    }

    // Apply saved settings
    QStringList keys = m_settings.allKeys();
    for (const QString &key : keys) {
        applySettingToMpv(key, m_settings.value(key));
    }

    // Create/register shortcuts dynamically using QShortcut
    for (const auto &sh : getShortcutDefinitions()) {
        QString keySeq = m_settings.value("shortcut" + sh.key, sh.defaultKey).toString();
        QShortcut *shortcut = new QShortcut(QKeySequence(keySeq), this);
        connect(shortcut, &QShortcut::activated, this, [this, sh]() {
            handleShortcutTrigger(sh.key);
        });
        m_shortcuts.insert(sh.key, shortcut);
    }
}

bool MainWindow::shouldShowWelcome() const
{
    return !m_welcomeSuppressed && m_settings.value("showWelcome", true).toBool();
}

int MainWindow::runWelcomeScreen()
{
    return m_welcomeWindow->exec();
}

MainWindow::~MainWindow()
{
    s_windowCount--;
    if (m_thumbnailMpv) {
        m_thumbnailMpv->shutdown();
        delete m_thumbnailMpv;
    }
    delete m_settingsWindow;
    delete m_rcloneBrowser;
}

void MainWindow::suppressWelcome()
{
    m_welcomeSuppressed = true;
}

void MainWindow::setupUi()
{
    setWindowTitle("Glass Player");
    resize(1280, 720);
    setMinimumSize(700, 400);
    setStyleSheet("QMainWindow { background-color: black; }");

    m_centralWidget = new QWidget(this);
    setCentralWidget(m_centralWidget);

    // Main layout is just the MPV widget filling everything
    QVBoxLayout *mainLayout = new QVBoxLayout(m_centralWidget);
    mainLayout->setContentsMargins(0, 0, 0, 0);
    mainLayout->setSpacing(0);

    m_mpvWidget = new MpvWidget(m_centralWidget);
    mainLayout->addWidget(m_mpvWidget);

    setupTopBar();
    setupBottomBar();
    setupBrightnessBar();
    setupVolumeBar();

    updateHudPositions();
}

void MainWindow::setupTopBar()
{
    m_topBar = new QWidget(m_mpvWidget);
    m_topBar->setObjectName("topBar");
    m_topBar->setFixedHeight(44);
    m_topBar->setStyleSheet(
        QString(
            "QWidget#topBar { "
            "  background-color: %1; "
            "}"
            "QPushButton { "
            "  background: transparent; color: %2; border: none; font-size: 16px; padding: 6px; border-radius: 4px; "
            "}"
            "QPushButton:hover { "
            "  background-color: %3; "
            "  color: %4; "
            "}"
            "QLabel { "
            "  color: %2; font-family: %5; font-weight: 500; font-size: 13px; "
            "}"
        ).arg(Theme::kBgSurface, Theme::kTextPrimary, Theme::kBgHover, Theme::kAccent, Theme::kFontFamily)
    );

    QHBoxLayout *layout = new QHBoxLayout(m_topBar);
    layout->setContentsMargins(15, 0, 15, 0);

    m_titleLabel = new QLabel(m_topBar);
    m_titleLabel->setStyleSheet(QString("QLabel { color: %1; font-family: %2; font-weight: 400; font-size: 13px; }").arg(Theme::kTextSecondary, Theme::kFontFamily));
    layout->addWidget(m_titleLabel);

    m_resolutionBadge = new QLabel(m_topBar);
    m_resolutionBadge->setObjectName("resolutionBadge");
    m_resolutionBadge->setStyleSheet(
        "QLabel#resolutionBadge { "
        "  background-color: rgba(255, 255, 255, 0.15); "
        "  color: white; "
        "  border-radius: 4px; "
        "  padding: 2px 6px; "
        "  font-size: 11px; "
        "  font-weight: bold; "
        "}"
    );
    layout->addWidget(m_resolutionBadge);
    m_resolutionBadge->hide();

    m_urlEdit = new QLineEdit(m_topBar);
    m_urlEdit->setPlaceholderText("Paste URL (YouTube, HTTP, etc.)");
    m_urlEdit->setStyleSheet(
        QString(
            "QLineEdit { "
            "  background: %1; "
            "  color: %2; "
            "  border: 1px solid %3; "
            "  border-radius: 4px; "
            "  padding: 4px 10px; "
            "  font-size: 13px; "
            "}"
            "QLineEdit:focus { "
            "  border: 1px solid %4; "
            "}"
        ).arg(Theme::kBgSurfaceSecondary, Theme::kTextPrimary, Theme::kBorderDefault, Theme::kAccent)
    );
    m_urlEdit->setFixedWidth(350);
    m_urlEdit->hide();
    connect(m_urlEdit, &QLineEdit::returnPressed, this, &MainWindow::onUrlSubmitted);

    layout->addStretch();
    layout->addWidget(m_urlEdit);

    QPushButton *urlBtn = new QPushButton(m_topBar);
    urlBtn->setIcon(QIcon(":/icons/url.svg"));
    urlBtn->setIconSize(QSize(20, 20));
    urlBtn->setFocusPolicy(Qt::NoFocus);
    connect(urlBtn, &QPushButton::clicked, this, &MainWindow::onUrlClicked);
    layout->addWidget(urlBtn);

    QPushButton *openBtn = new QPushButton(m_topBar);
    openBtn->setIcon(QIcon(":/icons/open_file.svg"));
    openBtn->setIconSize(QSize(20, 20));
    openBtn->setFocusPolicy(Qt::NoFocus);
    connect(openBtn, &QPushButton::clicked, this, &MainWindow::onOpenClicked);
    layout->addWidget(openBtn);

    QPushButton *remoteBtn = new QPushButton(m_topBar);
    remoteBtn->setIcon(QIcon(":/icons/remote.svg"));
    remoteBtn->setIconSize(QSize(20, 20));
    remoteBtn->setFocusPolicy(Qt::NoFocus);
    connect(remoteBtn, &QPushButton::clicked, this, &MainWindow::onRcloneClicked);
    layout->addWidget(remoteBtn);

    QPushButton *settingsBtn = new QPushButton(m_topBar);
    settingsBtn->setIcon(QIcon(":/icons/settings.svg"));
    settingsBtn->setIconSize(QSize(20, 20));
    settingsBtn->setFocusPolicy(Qt::NoFocus);
    connect(settingsBtn, &QPushButton::clicked, this, &MainWindow::onSettingsClicked);
    layout->addWidget(settingsBtn);

    m_topBar->show();
}

void MainWindow::setupBottomBar()
{
    m_bottomBar = new QWidget(m_mpvWidget);
    m_bottomBar->setObjectName("bottomBar");
    m_bottomBar->setFixedHeight(90);
    m_bottomBar->setStyleSheet(
        QString(
            "QWidget#bottomBar { "
            "  background-color: %1; "
            "  border: 1px solid %2; "
            "  border-radius: 8px; "
            "}"
            "QPushButton { "
            "  background: transparent; color: %3; border: none; font-size: 18px; min-width: 30px; border-radius: 4px; "
            "}"
            "QPushButton#playPause { "
            "  background-color: %4; border-radius: 20px; min-width: 40px; min-height: 40px; font-size: 20px; "
            "}"
            "QPushButton#playPause:hover { background-color: rgba(96, 205, 255, 80); }"
            "QPushButton:hover { background: %5; }"
            "QLabel { color: %3; font-size: 11px; font-family: %6; }"
        ).arg(Theme::kBgSurface, Theme::kBorderElevated, Theme::kTextPrimary, Theme::kAccentSubtle, Theme::kBgHover, Theme::kFontMono)
        + Theme::kSliderHorizontalStyle
    );

    m_currentTimeLabel = new QLabel("0:00", m_bottomBar);
    m_currentTimeLabel->setFixedWidth(60);

    m_seekSlider = new ClickableSlider(Qt::Horizontal, m_bottomBar);
    m_seekSlider->setRange(0, 1000000);
    m_seekSlider->setMouseTracking(true);
    m_seekSlider->setFocusPolicy(Qt::NoFocus);
    m_seekSlider->installEventFilter(this);
    connect(m_seekSlider, &QSlider::sliderMoved, this, &MainWindow::onSliderMoved);
    connect(m_seekSlider, &QSlider::sliderReleased, this, &MainWindow::onSliderReleased);

    m_remainingTimeLabel = new QLabel("-0:00", m_bottomBar);
    m_remainingTimeLabel->setFixedWidth(60);
    m_remainingTimeLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);

    m_subtitleBtn = new QPushButton(m_bottomBar);
    m_subtitleBtn->setIcon(QIcon(":/icons/subtitle.svg"));
    m_subtitleBtn->setFocusPolicy(Qt::NoFocus);
    connect(m_subtitleBtn, &QPushButton::clicked, this, &MainWindow::onSubtitleClicked);
 
    m_audioBtn = new QPushButton(m_bottomBar);
    m_audioBtn->setIcon(QIcon(":/icons/audio.svg"));
    m_audioBtn->setFocusPolicy(Qt::NoFocus);
    connect(m_audioBtn, &QPushButton::clicked, this, &MainWindow::onAudioClicked);
 
    m_shaderBtn = new QPushButton(m_bottomBar);
    m_shaderBtn->setIcon(QIcon(":/icons/shader.svg"));
    m_shaderBtn->setFocusPolicy(Qt::NoFocus);
    connect(m_shaderBtn, &QPushButton::clicked, this, &MainWindow::onShaderClicked);
 
    m_rewindBtn = new QPushButton(m_bottomBar);
    m_rewindBtn->setIcon(QIcon(":/icons/rewind.svg"));
    m_rewindBtn->setFocusPolicy(Qt::NoFocus);
    m_prevBtn = new QPushButton(m_bottomBar);
    m_prevBtn->setIcon(QIcon(":/icons/prev.svg"));
    m_prevBtn->setFocusPolicy(Qt::NoFocus);
    m_playPauseBtn = new QPushButton(m_bottomBar);
    m_playPauseBtn->setIcon(QIcon(":/icons/pause.svg"));
    m_playPauseBtn->setObjectName("playPause");
    m_playPauseBtn->setIconSize(QSize(24, 24));
    m_playPauseBtn->setFocusPolicy(Qt::NoFocus);
    m_nextBtn = new QPushButton(m_bottomBar);
    m_nextBtn->setIcon(QIcon(":/icons/next.svg"));
    m_nextBtn->setFocusPolicy(Qt::NoFocus);
    m_forwardBtn = new QPushButton(m_bottomBar);
    m_forwardBtn->setIcon(QIcon(":/icons/forward.svg"));
    m_forwardBtn->setFocusPolicy(Qt::NoFocus);

    connect(m_rewindBtn, &QPushButton::clicked, this, &MainWindow::onRewindClicked);
    connect(m_prevBtn, &QPushButton::clicked, this, &MainWindow::onPrevClicked);
    connect(m_playPauseBtn, &QPushButton::clicked, this, &MainWindow::onPlayPauseClicked);
    connect(m_nextBtn, &QPushButton::clicked, this, &MainWindow::onNextClicked);
    connect(m_forwardBtn, &QPushButton::clicked, this, &MainWindow::onForwardClicked);

    m_volumeBtn = new QPushButton(m_bottomBar);
    m_volumeBtn->setIcon(QIcon(":/icons/volume_mid.svg"));
    m_volumeBtn->setFocusPolicy(Qt::NoFocus);
    connect(m_volumeBtn, &QPushButton::clicked, this, &MainWindow::onMuteClicked);
 
    m_volumeSlider = new ClickableSlider(Qt::Horizontal, m_bottomBar);
    m_volumeSlider->setRange(0, 200);
    m_volumeSlider->setValue(100);
    m_volumeSlider->setFixedWidth(70);
    m_volumeSlider->setFocusPolicy(Qt::NoFocus);
    m_volumeSlider->setStyleSheet(
        "QSlider::horizontal { height: 16px; background: transparent; } " + Theme::kSliderHorizontalStyle
    );
    connect(m_volumeSlider, &QSlider::valueChanged, this, &MainWindow::onVolumeChanged);

    m_speedBtn = new QPushButton("1x", m_bottomBar);
    m_speedBtn->setStyleSheet(QString("font-weight: 600; font-size: 12px; font-family: %1;").arg(Theme::kFontFamily));
    m_speedBtn->setFocusPolicy(Qt::NoFocus);
    connect(m_speedBtn, &QPushButton::clicked, this, &MainWindow::onSpeedClicked);
    
    m_aspectBtn = new QPushButton(m_bottomBar);
    m_aspectBtn->setIcon(QIcon(":/icons/aspect.svg"));
    m_aspectBtn->setFocusPolicy(Qt::NoFocus);
    connect(m_aspectBtn, &QPushButton::clicked, this, &MainWindow::onAspectClicked);
    m_fullscreenBtn = new QPushButton(m_bottomBar);
    m_fullscreenBtn->setIcon(QIcon(":/icons/fullscreen.svg"));
    m_fullscreenBtn->setFocusPolicy(Qt::NoFocus);
    connect(m_fullscreenBtn, &QPushButton::clicked, this, &MainWindow::toggleFullscreen);

    // Set icon sizes for all buttons in controls row
    QList<QPushButton*> btns = m_bottomBar->findChildren<QPushButton*>();
    for (QPushButton* btn : btns) {
        if (btn != m_playPauseBtn && btn != m_speedBtn) {
            btn->setIconSize(QSize(20, 20));
        }
    }
}

void MainWindow::setupBrightnessBar()
{
    m_brightnessBar = new QWidget(m_mpvWidget);
    m_brightnessBar->setObjectName("brightnessBar");
    m_brightnessBar->setFixedWidth(40);
    m_brightnessBar->setFixedHeight(200);
    m_brightnessBar->setStyleSheet(
        QString(
            "QWidget#brightnessBar { "
            "  background-color: %1; "
            "  border: 1px solid %2; "
            "  border-radius: 8px; "
            "} "
        ).arg(Theme::kBgSurface, Theme::kBorderElevated) + Theme::kSliderVerticalStyle
    );

    QVBoxLayout *layout = new QVBoxLayout(m_brightnessBar);
    layout->setContentsMargins(0, 15, 0, 15);
    layout->setAlignment(Qt::AlignHCenter);

    QLabel *icon = new QLabel(m_brightnessBar);
    icon->setPixmap(QIcon(":/icons/sun.svg").pixmap(16, 16));
    icon->setFixedSize(16, 16);
    icon->setScaledContents(true);
    layout->addWidget(icon, 0, Qt::AlignHCenter);

    m_brightnessSlider = new ClickableSlider(Qt::Vertical, m_brightnessBar);
    m_brightnessSlider->setRange(0, 100);
    m_brightnessSlider->setValue(50); // Default to 50 (normal software brightness)
    m_brightnessSlider->setFixedWidth(20);
    m_brightnessSlider->setFocusPolicy(Qt::NoFocus);
    connect(m_brightnessSlider, &QSlider::valueChanged, this, &MainWindow::onBrightnessChanged);
    layout->addWidget(m_brightnessSlider, 0, Qt::AlignHCenter);

    m_brightnessBar->hide(); // Hidden by default, appears on edge hover
}

void MainWindow::setupVolumeBar()
{
    m_volumeBar = new QWidget(m_mpvWidget);
    m_volumeBar->setObjectName("volumeBar");
    m_volumeBar->setFixedWidth(40);
    m_volumeBar->setFixedHeight(200);
    m_volumeBar->setStyleSheet(
        QString(
            "QWidget#volumeBar { "
            "  background-color: %1; "
            "  border: 1px solid %2; "
            "  border-radius: 8px; "
            "} "
        ).arg(Theme::kBgSurface, Theme::kBorderElevated) + Theme::kSliderVerticalStyle
    );

    QVBoxLayout *layout = new QVBoxLayout(m_volumeBar);
    layout->setContentsMargins(0, 15, 0, 15);
    layout->setAlignment(Qt::AlignHCenter);

    QLabel *icon = new QLabel(m_volumeBar);
    icon->setPixmap(QIcon(":/icons/volume_high.svg").pixmap(16, 16));
    icon->setFixedSize(16, 16);
    icon->setScaledContents(true);
    layout->addWidget(icon, 0, Qt::AlignHCenter);

    m_volumeHoverSlider = new ClickableSlider(Qt::Vertical, m_volumeBar);
    m_volumeHoverSlider->setRange(0, 100);
    m_volumeHoverSlider->setValue(50);
    m_volumeHoverSlider->setFixedWidth(20);
    m_volumeHoverSlider->setFocusPolicy(Qt::NoFocus);
    connect(m_volumeHoverSlider, &QSlider::valueChanged, this, &MainWindow::onVolumeChanged);
    layout->addWidget(m_volumeHoverSlider, 0, Qt::AlignHCenter);

    m_volumeBar->hide(); // Hidden by default, appears on edge hover
}

void MainWindow::updateHudPositions()
{
    if (!m_mpvWidget) return;
    int mw = m_mpvWidget->width();
    int mh = m_mpvWidget->height();

    if (m_topBar) {
        m_topBar->setGeometry(0, 0, mw, 44);
        m_topBar->raise();
    }
    if (m_bottomBar) {
        int w = mw - 32;
        int x = 16;
        int y = mh - 90 - 16;
        m_bottomBar->setGeometry(x, y, w, 90);
        
        // Absolute manual geometry layouts of all child controls inside m_bottomBar
        int bw = w;
        
        // Seek row
        if (m_currentTimeLabel) m_currentTimeLabel->setGeometry(14, 8, 60, 20);
        if (m_remainingTimeLabel) m_remainingTimeLabel->setGeometry(bw - 14 - 60, 8, 60, 20);
        if (m_seekSlider) m_seekSlider->setGeometry(80, 8, bw - 80 - 80, 20);
        
        // Vertically center buttons in controls row around Y=48
        int btnY = 48;
        
        // Center Group (Play controls)
        int playPauseWidth = 40;
        int playPauseX = (bw - playPauseWidth) / 2;
        if (m_playPauseBtn) m_playPauseBtn->setGeometry(playPauseX, btnY - 5, playPauseWidth, 40);
        
        int prevX = playPauseX - 6 - 30;
        if (m_prevBtn) m_prevBtn->setGeometry(prevX, btnY, 30, 30);
        
        int rewindX = prevX - 4 - 30;
        if (m_rewindBtn) m_rewindBtn->setGeometry(rewindX, btnY, 30, 30);
        
        int nextX = playPauseX + playPauseWidth + 6;
        if (m_nextBtn) m_nextBtn->setGeometry(nextX, btnY, 30, 30);
        
        int forwardX = nextX + 30 + 4;
        if (m_forwardBtn) m_forwardBtn->setGeometry(forwardX, btnY, 30, 30);
        
        // Left Group (Track selectors)
        if (m_subtitleBtn) m_subtitleBtn->setGeometry(14, btnY, 30, 30);
        if (m_audioBtn) m_audioBtn->setGeometry(14 + 30 + 6, btnY, 30, 30);
        if (m_shaderBtn) m_shaderBtn->setGeometry(14 + 30 + 6 + 30 + 6, btnY, 30, 30);
        
        // Right Group (Volume, Speed, Fullscreen)
        int fullscreenX = bw - 14 - 30;
        if (m_fullscreenBtn) m_fullscreenBtn->setGeometry(fullscreenX, btnY, 30, 30);
        
        int aspectX = fullscreenX - 6 - 30;
        if (m_aspectBtn) m_aspectBtn->setGeometry(aspectX, btnY, 30, 30);
        
        int speedX = aspectX - 6 - 32;
        if (m_speedBtn) m_speedBtn->setGeometry(speedX, btnY, 32, 30);
        
        int volumeSliderX = speedX - 8 - 70;
        if (m_volumeSlider) m_volumeSlider->setGeometry(volumeSliderX, btnY + 5, 70, 20);
        
        int volumeBtnX = volumeSliderX - 6 - 30;
        if (m_volumeBtn) m_volumeBtn->setGeometry(volumeBtnX, btnY, 30, 30);

        m_bottomBar->raise();
    }
    if (m_brightnessBar) {
        int x = 16;
        int y = (mh - 200) / 2;
        m_brightnessBar->setGeometry(x, y, 40, 200);
        m_brightnessBar->raise();
    }
    if (m_volumeBar) {
        int x = mw - 56;
        int y = (mh - 200) / 2;
        m_volumeBar->setGeometry(x, y, 40, 200);
        m_volumeBar->raise();
    }
}


void MainWindow::openFile(const QString &file)
{
    if (!file.isEmpty() && !file.contains("://")) {
        static const QStringList kSupportedExtensions = {
            "mp4", "mkv", "avi", "mov", "flv", "webm", "wmv", "m4v", "3gp", "ts", "mts", "m2ts", "vob", "ogv", "asf",
            "mp3", "m4a", "aac", "flac", "wav", "ac3", "dts", "ogg", "opus", "wma", "mka"
        };
        QFileInfo info(file);
        QString ext = info.suffix().toLower();
        if (!kSupportedExtensions.contains(ext)) {
            QMessageBox::warning(this, "Unsupported Format",
                QString("The file format '.%1' is not supported by Glass Player.\n\nPlease choose a compatible video or audio file.").arg(ext));
            return;
        }
    }

    if (!m_currentFile.isEmpty()) {
        if (s_windowCount >= 10) {
            QMessageBox::critical(this, "Window Limit Exceeded",
                "Maximum window limit (10) reached. Cannot open another video window.");
            return;
        } else if (s_windowCount >= 5) {
            QMessageBox::StandardButton reply = QMessageBox::warning(this, "Resource Warning",
                QString("You have %1 windows open. Opening more may affect performance. Do you want to proceed?").arg(s_windowCount),
                QMessageBox::Yes | QMessageBox::No);
            if (reply == QMessageBox::No) {
                return;
            }
        }
        MainWindow *newWin = new MainWindow();
        newWin->setAttribute(Qt::WA_DeleteOnClose);
        newWin->suppressWelcome();
        newWin->openFile(file);
        newWin->show();
        newWin->raise();
        newWin->activateWindow();
        return;
    }

    m_currentFile = file;
    QFileInfo fileInfo(file);
    QString displayName = fileInfo.fileName();
    if (displayName.isEmpty()) {
        displayName = file;
    }
    if (m_titleLabel) {
        m_titleLabel->setText(displayName);
    }

    m_thumbnailCache.clear();
    m_isGeneratingThumbnail = false;
    m_pendingThumbnailTime = -1;
    if (!m_thumbnailMpv) {
        m_thumbnailMpv = new ThumbnailMpv(this);
    }

    m_thumbnailMpv->loadSource(file);

    m_mpvWidget->loadFile(file);
    m_isPlaying = true;
    m_playPauseBtn->setIcon(QIcon(":/icons/pause.svg"));
}

void MainWindow::onOpenClicked()
{
    QFileDialog dialog(this, "Open Video");
    dialog.setWindowModality(Qt::ApplicationModal);
    dialog.setNameFilter("Media Files (*.mp4 *.mkv *.avi *.mov *.flv *.webm *.wmv *.m4v *.3gp *.ts *.mts *.m2ts *.vob *.ogv *.asf *.mp3 *.m4a *.aac *.flac *.wav *.ac3 *.dts *.ogg *.opus *.wma *.mka);;Video Files (*.mp4 *.mkv *.avi *.mov *.flv *.webm *.wmv *.m4v *.3gp *.ts *.mts *.m2ts *.vob *.ogv *.asf);;Audio Files (*.mp3 *.m4a *.aac *.flac *.wav *.ac3 *.dts *.ogg *.opus *.wma *.mka);;All Files (*.*)");
    if (dialog.exec() == QDialog::Accepted) {
        QString file = dialog.selectedFiles().first();
        if (!file.isEmpty()) {
            openFile(file);
        }
    }
}

void MainWindow::onRcloneClicked()
{
    m_rcloneBrowser->exec();
}

void MainWindow::onSettingsClicked()
{
    m_settingsWindow->exec();
}

void MainWindow::onFileLoaded()
{
    if (isFullScreen()) return;

    updateResolutionBadge();

    // Kickstart and unblock stuck demuxer/decoder
    m_mpvWidget->command(QVariantList() << "seek" << 0 << "absolute+exact");
    m_mpvWidget->setProperty("pause", false);

    if (!m_firstFileLoaded) {
        return;
    }

    QString behavior = m_settings.value("windowResize", "Never resize").toString();
    if (behavior == "Never resize") {
        m_firstFileLoaded = false;
        return;
    }

    int vw = m_mpvWidget->getProperty("video-params/w").toInt();
    int vh = m_mpvWidget->getProperty("video-params/h").toInt();
    if (vw <= 0 || vh <= 0) return;

    double scale = 1.0;
    if (behavior == "Resize to 50%") scale = 0.5;
    else if (behavior == "Resize to 75%") scale = 0.75;
    else if (behavior == "Resize to 100%") scale = 1.0;

    int targetW = qRound(vw * scale);
    int targetH = qRound(vh * scale);

    QScreen *screen = QGuiApplication::primaryScreen();
    if (screen) {
        QRect screenGeom = screen->availableGeometry();
        if (targetW > screenGeom.width() || targetH > screenGeom.height()) {
            double aspect = static_cast<double>(vw) / vh;
            if (targetW > screenGeom.width()) {
                targetW = screenGeom.width() - 80;
                targetH = qRound(targetW / aspect);
            }
            if (targetH > screenGeom.height()) {
                targetH = screenGeom.height() - 80;
                targetW = qRound(targetH * aspect);
            }
        }
    }

    resize(targetW, targetH);
    m_firstFileLoaded = false;
}

void MainWindow::changeEvent(QEvent *event)
{
    if (event->type() == QEvent::ActivationChange) {
        if (!isActiveWindow() && m_settings.value("pauseOnFocusLoss", false).toBool()) {
            if (m_isPlaying) {
                onPlayPauseClicked();
            }
        }
    } else if (event->type() == QEvent::WindowStateChange) {
        if (isMinimized()) {
            m_systemSyncTimer->stop();
        } else {
            m_systemSyncTimer->start();
        }
    }
    QMainWindow::changeEvent(event);
}

void MainWindow::onPlayPauseClicked()
{
    if (m_isPlaying) {
        m_mpvWidget->pause();
    } else {
        m_mpvWidget->play();
    }
}

void MainWindow::onSliderMoved(int position)
{
    m_isSeeking = true;
    if (m_duration > 0) {
        double pos = (position / 1000000.0) * m_duration;
        m_currentTimeLabel->setText(formatTime(pos));
        m_remainingTimeLabel->setText("-" + formatTime(m_duration - pos));

        qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - m_lastSeekTime > 25) {
            m_lastSeekTime = now;
            if (m_seekInProgress) {
                m_queuedSeekTarget = pos;
                m_seekCommandPending = true;
            } else {
                m_seekInProgress = true;
                m_seekTimeoutTimer->start();
                m_mpvWidget->command(QVariantList() << "seek" << QString::number(pos, 'f', 6) << "absolute+keyframes");
            }
        }
    }
}

void MainWindow::onSliderReleased()
{
    if (m_duration > 0) {
        double pos = (m_seekSlider->value() / 1000000.0) * m_duration;
        if (m_seekInProgress) {
            m_queuedSeekTarget = pos;
            m_seekCommandPending = true;
        } else {
            m_seekInProgress = true;
            m_seekTimeoutTimer->start();
            m_mpvWidget->command(QVariantList() << "seek" << QString::number(pos, 'f', 6) << "absolute+exact");
        }
        m_currentTimeLabel->setText(formatTime(pos));
        m_remainingTimeLabel->setText("-" + formatTime(m_duration - pos));
    }
    hideTimelinePreview();
}

void MainWindow::onVolumeChanged(int volume)
{
    if (m_syncingFromSystem) return;

    const int osVolume = qBound(0, volume, 100);
    const int mpvVolume = qBound(0, volume, 200);

    m_syncingFromSystem = true;
    {
        QSignalBlocker blocker1(m_volumeSlider);
        m_volumeSlider->setValue(mpvVolume);
    }
    {
        QSignalBlocker blocker2(m_volumeHoverSlider);
        m_volumeHoverSlider->setValue(osVolume);
    }
    m_syncingFromSystem = false;

    // Set OS system volume and mute state
    WinOSIntegration::instance().setSystemVolume(osVolume / 100.0f);
    WinOSIntegration::instance().setMuted(volume == 0);

    // Set mpv volume to match (up to 200%)
    m_mpvWidget->setVolume(mpvVolume);
    updateVolumeIcon(mpvVolume, volume == 0);
}

void MainWindow::onMuteClicked()
{
    m_isMuted = !m_isMuted;
    WinOSIntegration::instance().setMuted(m_isMuted);
    m_mpvWidget->setProperty("mute", m_isMuted ? "yes" : "no");
    updateVolumeIcon(m_volumeSlider->value(), m_isMuted);
}

// Copy shader from qrc to temp dir on first use
static QString extractShader(const QString& name) {
    static QTemporaryDir tempDir;
    QString baseDir;
    if (tempDir.isValid()) {
        baseDir = tempDir.path();
    } else {
        baseDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/shaders";
        QDir().mkpath(baseDir);
    }
    const QString outPath = baseDir + "/" + name;
    QFile outFile(outPath);
    if (!outFile.exists()) {
        QFile src(":/shaders/" + name);
        if (src.open(QIODevice::ReadOnly) && outFile.open(QIODevice::WriteOnly))
            outFile.write(src.readAll());
    }
    return outPath;
}



void MainWindow::applySettingToMpv(const QString &key, const QVariant &value)
{
    if (key.startsWith("shortcut")) {
        QString shKey = key.mid(8);
        if (m_shortcuts.contains(shKey)) {
            m_shortcuts[shKey]->setKey(QKeySequence(value.toString()));
        }
        return;
    }

    // General
    if (key == "resumePlayback") {
        m_mpvWidget->setProperty("save-position-on-quit", value.toBool() ? "yes" : "no");
    } else if (key == "quitWhenAllClosed") {
        QGuiApplication::setQuitOnLastWindowClosed(value.toBool());
    } else if (key == "keepOnTop") {
        bool onTop = value.toBool();
        Qt::WindowFlags flags = windowFlags();
        if (onTop) {
            flags |= Qt::WindowStaysOnTopHint;
        } else {
            flags &= ~Qt::WindowStaysOnTopHint;
        }
        setWindowFlags(flags);
        show();
    }

    // Video
    else if (key == "hwdec") {
        m_mpvWidget->setProperty("hwdec", value.toString());
    } else if (key == "hwdecCodecs") {
        m_mpvWidget->setProperty("hwdec-codecs", value.toString());
    } else if (key == "defaultSpeed") {
        QString s = value.toString().remove("x");
        m_mpvWidget->setProperty("speed", s.toDouble());
    } else if (key == "screenshotFormat") {
        m_mpvWidget->setProperty("screenshot-format", value.toString());
    } else if (key == "screenshotJpegQuality") {
        m_mpvWidget->setProperty("screenshot-jpeg-quality", value.toInt());
    } else if (key == "debandEnabled") {
        m_mpvWidget->setProperty("deband", value.toBool() ? "yes" : "no");
    } else if (key == "debandIterations") {
        m_mpvWidget->setProperty("deband-iterations", value.toInt());
    } else if (key == "debandThreshold") {
        m_mpvWidget->setProperty("deband-threshold", value.toInt());
    } else if (key == "debandRange") {
        m_mpvWidget->setProperty("deband-range", value.toInt());
    } else if (key == "debandGrain") {
        m_mpvWidget->setProperty("deband-grain", value.toInt());
    }
    // Audio
    else if (key == "volumeMax") {
        QString s = value.toString().remove("%");
        m_mpvWidget->setProperty("volume-max", s.toInt());
    } else if (key == "audioOutput") {
        m_mpvWidget->setProperty("ao", value.toString());
    } else if (key == "audioChannels") {
        m_mpvWidget->setProperty("audio-channels", value.toString());
    } else if (key == "audioPassthrough") {
        m_mpvWidget->setProperty("audio-spdif", value.toBool() ? "ac3,eac3,truehd,dts-hd" : "");
    } else if (key == "audioLang") {
        m_mpvWidget->setProperty("alang", value.toString());
    } else if (key == "audioDelay") {
        m_mpvWidget->setProperty("audio-delay", value.toDouble());
    } else if (key == "defaultVolume") {
        m_mpvWidget->setProperty("volume", value.toInt());
    }
    // Subtitles
    else if (key == "subAutoLoad") {
        m_mpvWidget->setProperty("sub-auto", value.toBool() ? "all" : "no");
    } else if (key == "subLang") {
        m_mpvWidget->setProperty("slang", value.toString());
    } else if (key == "subFontSize") {
        m_mpvWidget->setProperty("sub-font-size", value.toInt());
    } else if (key == "subFont") {
        QString font = value.toString();
        if (font != "(Default)") m_mpvWidget->setProperty("sub-font", font);
    } else if (key == "subPosition") {
        m_mpvWidget->setProperty("sub-pos", value.toString() == "Bottom" ? 100 : 0);
    } else if (key == "subBorderSize") {
        m_mpvWidget->setProperty("sub-border-size", value.toInt());
    } else if (key == "subShadowOffset") {
        m_mpvWidget->setProperty("sub-shadow-offset", value.toInt());
    } else if (key == "subAssOverride") {
        m_mpvWidget->setProperty("sub-ass-override", value.toBool() ? "yes" : "no");
    }
    // Network
    else if (key == "cacheEnabled") {
        m_mpvWidget->setProperty("cache", value.toBool() ? "yes" : "no");
    } else if (key == "cacheSizeMB") {
        QString s = value.toString().remove(" MB");
        int64_t bytes = static_cast<int64_t>(s.toInt()) * 1024 * 1024;
        m_mpvWidget->setProperty("demuxer-max-bytes", QVariant::fromValue(bytes));
    } else if (key == "cacheBackMB") {
        QString s = value.toString().remove(" MB");
        int64_t bytes = static_cast<int64_t>(s.toInt()) * 1024 * 1024;
        m_mpvWidget->setProperty("demuxer-max-back-bytes", QVariant::fromValue(bytes));
    } else if (key == "readaheadSecs") {
        m_mpvWidget->setProperty("demuxer-readahead-secs", value.toInt());
    } else if (key == "cacheSecs") {
        m_mpvWidget->setProperty("cache-secs", value.toInt());
    } else if (key == "networkTimeout") {
        m_mpvWidget->setProperty("network-timeout", value.toInt());
    } else if (key == "forceSeekable") {
        m_mpvWidget->setProperty("force-seekable", value.toBool() ? "yes" : "no");
    } else if (key == "reconnect") {
        m_mpvWidget->setProperty("reconnect", value.toBool() ? "yes" : "no");
    } else if (key == "userAgent") {
        QString ua = value.toString();
        if (ua != "(Default)") m_mpvWidget->setProperty("user-agent", ua);
    }
    // Scaling
    else if (key == "videoProfile") {
        m_mpvWidget->setProperty("profile", value.toString());
    } else if (key == "scaleFilter") {
        m_mpvWidget->setProperty("scale", value.toString());
    } else if (key == "dscaleFilter") {
        m_mpvWidget->setProperty("dscale", value.toString());
    } else if (key == "cscaleFilter") {
        m_mpvWidget->setProperty("cscale", value.toString());
    } else if (key == "ditherDepth") {
        m_mpvWidget->setProperty("dither-depth", value.toString());
    } else if (key == "ditherAlgo") {
        m_mpvWidget->setProperty("dither", value.toString());
    } else if (key == "correctDownscaling") {
        m_mpvWidget->setProperty("correct-downscaling", value.toBool() ? "yes" : "no");
    } else if (key == "linearDownscaling") {
        m_mpvWidget->setProperty("linear-downscaling", value.toBool() ? "yes" : "no");
    } else if (key == "sigmoidUpscaling") {
        m_mpvWidget->setProperty("sigmoid-upscaling", value.toBool() ? "yes" : "no");
    }
    // Color
    else if (key == "toneMapping") {
        m_mpvWidget->setProperty("tone-mapping", value.toString());
    } else if (key == "toneMappingMode") {
        m_mpvWidget->setProperty("tone-mapping-mode", value.toString());
    } else if (key == "hdrComputePeak") {
        m_mpvWidget->setProperty("hdr-compute-peak", value.toBool() ? "yes" : "no");
    } else if (key == "targetColorspaceHint") {
        m_mpvWidget->setProperty("target-colorspace-hint", value.toBool() ? "yes" : "no");
    } else if (key == "targetPeak") {
        m_mpvWidget->setProperty("target-peak", value.toString());
    } else if (key == "gamutMapping") {
        m_mpvWidget->setProperty("gamut-mapping-mode", value.toString());
    } else if (key == "iccProfile") {
        QString icc = value.toString();
        if (icc != "(None)") m_mpvWidget->setProperty("icc-profile", icc);
    }
    // Anime4K
    else if (key == "defaultShaderPreset") {
        applyShaderPreset(value.toString());
    }
}

void MainWindow::setAnime4kPreset(const QString& preset)
{
    applyShaderPreset(preset);
}

void MainWindow::applyShaderPreset(const QString& preset)
{
    static const QHash<QString, QString> aliases = {
        {"ModeA", "Mode A (HQ)"},
        {"ModeB", "Mode B (HQ)"},
        {"ModeC", "Mode C (HQ)"},
        {"ModeAA", "Mode A+A (HQ)"},
        {"ModeBB", "Mode B+B (HQ)"},
        {"ModeCA", "Mode C+A (HQ)"},
        {"ModeAFast", "Mode A (Fast)"},
        {"ModeBFast", "Mode B (Fast)"},
        {"ModeCFast", "Mode C (Fast)"},
        {"ModeAAFast", "Mode A+A (Fast)"},
        {"ModeBBFast", "Mode B+B (Fast)"},
        {"ModeCAFast", "Mode C+A (Fast)"}
    };

    const QString resolvedPreset = aliases.value(preset, preset);

    if (resolvedPreset.isEmpty() || resolvedPreset == "Off") {
        m_mpvWidget->command(QVariantList() << "change-list" << "glsl-shaders" << "clr" << "");
        m_shaderBtn->setGraphicsEffect(nullptr);
        m_shaderBtn->setStyleSheet("");
        return;
    }

    static const QHash<QString, QStringList> kShaderPresets = {
        {"Mode A (HQ)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Restore_CNN_VL.glsl", "Anime4K_Upscale_CNN_x2_VL.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_M.glsl"}},
        {"Mode B (HQ)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Restore_CNN_Soft_VL.glsl", "Anime4K_Upscale_CNN_x2_VL.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_M.glsl"}},
        {"Mode C (HQ)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_M.glsl"}},
        {"Mode A+A (HQ)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Restore_CNN_VL.glsl", "Anime4K_Upscale_CNN_x2_VL.glsl", "Anime4K_Restore_CNN_M.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_M.glsl"}},
        {"Mode B+B (HQ)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Restore_CNN_Soft_VL.glsl", "Anime4K_Upscale_CNN_x2_VL.glsl", "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_M.glsl"}},
        {"Mode C+A (HQ)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Restore_CNN_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl"}},
        {"Mode A (Fast)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Restore_CNN_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_S.glsl"}},
        {"Mode B (Fast)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_S.glsl"}},
        {"Mode C (Fast)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Upscale_Denoise_CNN_x2_M.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_S.glsl"}},
        {"Mode A+A (Fast)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Restore_CNN_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_Restore_CNN_S.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Upscale_CNN_x2_S.glsl"}},
        {"Mode B+B (Fast)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Restore_CNN_Soft_S.glsl", "Anime4K_Upscale_CNN_x2_S.glsl"}},
        {"Mode C+A (Fast)", {"Anime4K_Clamp_Highlights.glsl", "Anime4K_Upscale_Denoise_CNN_x2_M.glsl", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_Restore_CNN_S.glsl", "Anime4K_Upscale_CNN_x2_S.glsl"}}
    };

    QStringList shaders;
    const QStringList shaderNames = kShaderPresets.value(resolvedPreset);
    for (const QString& shaderName : shaderNames) {
        const QString path = extractShader(shaderName);
        if (!path.isEmpty()) {
            shaders << QDir::toNativeSeparators(path);
        }
    }

    // Join shaders with path separator and set to mpv
    // mpv expects a colon-separated list on linux/mac, but semicolon-separated on Windows
#ifdef Q_OS_WIN
    QString shaderStr = shaders.join(";");
#else
    QString shaderStr = shaders.join(":");
#endif

    m_mpvWidget->command(QVariantList() << "change-list" << "glsl-shaders" << "set" << shaderStr);

    // Apply beautiful accent blue glow to the shader button when one is active
    QGraphicsDropShadowEffect *glow = new QGraphicsDropShadowEffect(m_shaderBtn);
    glow->setBlurRadius(15);
    glow->setColor(QColor(96, 205, 255, 200)); // vibrant accent blue glow (#60CDFF)
    glow->setOffset(0, 0);
    m_shaderBtn->setGraphicsEffect(glow);
    m_shaderBtn->setStyleSheet(
        QString(
            "QPushButton { "
            "  background: %1; "
            "  border: 1px solid %2; "
            "  border-radius: 4px; "
            "}"
        ).arg(Theme::kAccentSubtle, Theme::kAccent)
    );
}

QString MainWindow::formatTime(double seconds)
{
    const int total = static_cast<int>(seconds);
    const int h = total / 3600;
    const int m = (total % 3600) / 60;
    const int s = total % 60;
    if (h > 0)
        return QString::asprintf("%02d:%02d:%02d", h, m, s);
    return QString::asprintf("%02d:%02d", m, s);
}

void MainWindow::updatePosition(double position)
{
    m_lastPositionTime = QDateTime::currentMSecsSinceEpoch();
    if (m_isSeeking) return;
    if (!m_seekSlider->isSliderDown() && m_duration > 0) {
        m_seekSlider->setValue((position / m_duration) * 1000000.0);
    }
    m_currentTimeLabel->setText(formatTime(position));
    m_remainingTimeLabel->setText("-" + formatTime(m_duration - position));
}

void MainWindow::updateDuration(double duration)
{
    m_duration = duration;
    m_lastPositionTime = QDateTime::currentMSecsSinceEpoch();
}

void MainWindow::onStartFile()
{
    // Reset UI state for the new file that is beginning to load.
    // Clears stale slider position, labels, seeking flag, and thumbnail cache
    // so the player feels fresh for every new file.
    m_isSeeking = false;
    m_duration = 0;
    m_lastPositionTime = QDateTime::currentMSecsSinceEpoch();

    {
        QSignalBlocker blocker(m_seekSlider);
        m_seekSlider->setValue(0);
    }
    m_currentTimeLabel->setText(QStringLiteral("0:00"));
    m_remainingTimeLabel->setText(QStringLiteral("-0:00"));

    m_thumbnailCache.clear();
    m_pendingThumbnailTime = -1;
    m_isGeneratingThumbnail = false;
    hideTimelinePreview();

    // Mark playing so the watchdog baseline is refreshed
    m_isPlaying = true;
    m_playPauseBtn->setIcon(QIcon(":/icons/pause.svg"));
}

void MainWindow::resizeEvent(QResizeEvent *event)
{
    QMainWindow::resizeEvent(event);
    updateHudPositions();
    updateResolutionBadge();
}

void MainWindow::onRewindClicked() { m_mpvWidget->seek(-5.0); }
void MainWindow::onForwardClicked() { m_mpvWidget->seek(5.0); }
void MainWindow::onPrevClicked() { m_mpvWidget->command(QVariantList() << "playlist-prev"); }
void MainWindow::onNextClicked() { m_mpvWidget->command(QVariantList() << "playlist-next"); }
void MainWindow::onSpeedClicked()
{
    QMenu menu(this);
    Qt::WindowFlags flags = menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint;
    if (windowFlags() & Qt::WindowStaysOnTopHint) {
        flags |= Qt::WindowStaysOnTopHint;
    } else {
        flags &= ~Qt::WindowStaysOnTopHint;
    }
    menu.setWindowFlags(flags);
    menu.setAttribute(Qt::WA_TranslucentBackground);

    menu.setStyleSheet(kMenuStyle);

    double currentSpeed = m_mpvWidget->getProperty("speed").toDouble();
    if (currentSpeed <= 0) currentSpeed = 1.0;

    for (double s : {0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0}) {
        QAction *action = menu.addAction(QString::number(s) + "x", this, [this, s]() {
            m_mpvWidget->setProperty("speed", s);
            m_speedBtn->setText(s == static_cast<int>(s)
                ? QString::number(static_cast<int>(s)) + "x"
                : QString::number(s) + "x");
        });
        action->setCheckable(true);
        action->setChecked(qAbs(currentSpeed - s) < 0.01);
    }
    m_hudTimer->stop();
    menu.exec(m_speedBtn->mapToGlobal(QPoint(0, -menu.sizeHint().height())));
    showHud();
}

void MainWindow::onAspectClicked()
{
    QMenu menu(this);
    Qt::WindowFlags flags = menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint;
    if (windowFlags() & Qt::WindowStaysOnTopHint) {
        flags |= Qt::WindowStaysOnTopHint;
    } else {
        flags &= ~Qt::WindowStaysOnTopHint;
    }
    menu.setWindowFlags(flags);
    menu.setAttribute(Qt::WA_TranslucentBackground);

    menu.setStyleSheet(kMenuStyle);

    QString currentAspect = m_mpvWidget->getProperty("video-aspect-override").toString();
    if (currentAspect.toDouble() <= 0) currentAspect = "auto";

    static const std::pair<const char*, const char*> kAspects[] = {
        {"auto", "Auto"}, {"16:9", "16:9"}, {"16:10", "16:10"},
        {"4:3", "4:3"}, {"21:9", "21:9"}, {"2.35:1", "2.35:1"}
    };
    for (const auto& [key, label] : kAspects) {
        const QString qkey = QLatin1String(key);
        QAction *action = menu.addAction(QLatin1String(label), this, [this, qkey]() {
            m_mpvWidget->setProperty("video-aspect-override", qkey == "auto" ? "-1" : qkey);
        });
        action->setCheckable(true);
        action->setChecked(currentAspect == qkey ||
            (qkey == "auto" && (currentAspect.isEmpty() || currentAspect == "-1")));
    }
    m_hudTimer->stop();
    menu.exec(m_aspectBtn->mapToGlobal(QPoint(0, -menu.sizeHint().height())));
    showHud();
}

void MainWindow::onSubtitleClicked()
{
    QMenu menu(this);
    Qt::WindowFlags flags = menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint;
    if (windowFlags() & Qt::WindowStaysOnTopHint) {
        flags |= Qt::WindowStaysOnTopHint;
    } else {
        flags &= ~Qt::WindowStaysOnTopHint;
    }
    menu.setWindowFlags(flags);
    menu.setAttribute(Qt::WA_TranslucentBackground);

    menu.setStyleSheet(kMenuStyle);

    QList<TrackInfo> subTracks;
    for (const auto& track : getTracks())
        if (track.type == "sub") subTracks << track;

    const bool anySelected = std::any_of(subTracks.cbegin(), subTracks.cend(),
        [](const TrackInfo& t){ return t.selected; });

    QAction *offAction = menu.addAction("Off", this, [this]() { setSubtitleTrack(-1); });
    offAction->setCheckable(true);
    offAction->setChecked(!anySelected);
    menu.addSeparator();

    for (const auto& track : subTracks) {
        QAction *action = menu.addAction(track.label, this, [this, track]() {
            setSubtitleTrack(track.id);
        });
        action->setCheckable(true);
        action->setChecked(track.selected);
    }
    if (subTracks.isEmpty()) {
        menu.addAction("No subtitles available")->setEnabled(false);
    }
    menu.addSeparator();
    menu.addAction("Add External Subtitle...", this, &MainWindow::addExternalSubtitle);

    m_hudTimer->stop();
    menu.exec(m_subtitleBtn->mapToGlobal(QPoint(0, -menu.sizeHint().height())));
    showHud();
}

void MainWindow::onAudioClicked()
{
    QMenu menu(this);
    Qt::WindowFlags flags = menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint;
    if (windowFlags() & Qt::WindowStaysOnTopHint) {
        flags |= Qt::WindowStaysOnTopHint;
    } else {
        flags &= ~Qt::WindowStaysOnTopHint;
    }
    menu.setWindowFlags(flags);
    menu.setAttribute(Qt::WA_TranslucentBackground);

    menu.setStyleSheet(kMenuStyle);

    QList<TrackInfo> audioTracks;
    for (const auto& track : getTracks())
        if (track.type == "audio") audioTracks << track;

    for (const auto& track : audioTracks) {
        QAction *action = menu.addAction(track.label, this, [this, track]() {
            setAudioTrack(track.id);
        });
        action->setCheckable(true);
        action->setChecked(track.selected);
    }
    if (audioTracks.isEmpty())
        menu.addAction("No audio tracks available")->setEnabled(false);
    menu.addSeparator();
    menu.addAction("Add External Audio...", this, &MainWindow::addExternalAudio);

    m_hudTimer->stop();
    menu.exec(m_audioBtn->mapToGlobal(QPoint(0, -menu.sizeHint().height())));
    showHud();
}

void MainWindow::onShaderClicked()
{
    QMenu menu(this);
    Qt::WindowFlags flags = menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint;
    if (windowFlags() & Qt::WindowStaysOnTopHint) {
        flags |= Qt::WindowStaysOnTopHint;
    } else {
        flags &= ~Qt::WindowStaysOnTopHint;
    }
    menu.setWindowFlags(flags);
    menu.setAttribute(Qt::WA_TranslucentBackground);

    menu.setStyleSheet(kMenuStyle);

    QString currentPreset = m_settings.value("defaultShaderPreset", "Off").toString();

    QAction *offAction = menu.addAction("Off", this, [this]() {
        applySettingToMpv("defaultShaderPreset", "Off");
        m_settings.setValue("defaultShaderPreset", "Off");
    });
    offAction->setCheckable(true);
    offAction->setChecked(currentPreset == "Off");

    menu.addSeparator();

    // HQ Header
    QAction *hqHeader = menu.addAction("── HQ (Pro/Max GPU) ──");
    hqHeader->setEnabled(false);

    QStringList hqPresets = {"Mode A (HQ)", "Mode B (HQ)", "Mode C (HQ)",
                             "Mode A+A (HQ)", "Mode B+B (HQ)", "Mode C+A (HQ)"};
    for (const auto& preset : hqPresets) {
        QAction *action = menu.addAction(preset, this, [this, preset]() {
            applySettingToMpv("defaultShaderPreset", preset);
            m_settings.setValue("defaultShaderPreset", preset);
        });
        action->setCheckable(true);
        action->setChecked(currentPreset == preset);
    }

    menu.addSeparator();

    // Fast Header
    QAction *fastHeader = menu.addAction("── Fast (Lower GPU load) ──");
    fastHeader->setEnabled(false);

    QStringList fastPresets = {"Mode A (Fast)", "Mode B (Fast)", "Mode C (Fast)",
                               "Mode A+A (Fast)", "Mode B+B (Fast)", "Mode C+A (Fast)"};
    for (const auto& preset : fastPresets) {
        QAction *action = menu.addAction(preset, this, [this, preset]() {
            applySettingToMpv("defaultShaderPreset", preset);
            m_settings.setValue("defaultShaderPreset", preset);
        });
        action->setCheckable(true);
        action->setChecked(currentPreset == preset);
    }

    m_hudTimer->stop();
    menu.exec(m_shaderBtn->mapToGlobal(QPoint(0, -menu.sizeHint().height())));
    showHud();
}

QList<MainWindow::TrackInfo> MainWindow::getTracks()
{
    QList<TrackInfo> tracks;
    QVariant countVar = m_mpvWidget->getProperty("track-list/count");
    if (!countVar.isValid()) return tracks;
    int count = countVar.toInt();
    tracks.reserve(count);

    char buf[128];
    for (int i = 0; i < count; ++i) {
        TrackInfo track;

        snprintf(buf, sizeof(buf), "track-list/%d/id", i);
        track.id = m_mpvWidget->getProperty(buf).toInt();

        snprintf(buf, sizeof(buf), "track-list/%d/type", i);
        track.type = m_mpvWidget->getProperty(buf).toString();

        snprintf(buf, sizeof(buf), "track-list/%d/title", i);
        QString title = m_mpvWidget->getProperty(buf).toString();

        snprintf(buf, sizeof(buf), "track-list/%d/lang", i);
        QString lang = m_mpvWidget->getProperty(buf).toString().toUpper();

        snprintf(buf, sizeof(buf), "track-list/%d/codec", i);
        QString codec = m_mpvWidget->getProperty(buf).toString();

        snprintf(buf, sizeof(buf), "track-list/%d/selected", i);
        track.selected = (m_mpvWidget->getProperty(buf).toString() == "yes");

        QStringList parts;
        if (!title.isEmpty()) parts << title;
        if (!lang.isEmpty()) parts << lang;
        if (!codec.isEmpty()) parts << codec;
        if (parts.isEmpty()) parts << QString("Track %1").arg(track.id);
        track.label = parts.join(" · ");

        tracks << track;
    }
    return tracks;
}

void MainWindow::setSubtitleTrack(int id)
{
    if (id < 0) {
        m_mpvWidget->setProperty("sid", "no");
    } else {
        m_mpvWidget->setProperty("sid", id);
    }
}

void MainWindow::setAudioTrack(int id)
{
    m_mpvWidget->setProperty("aid", id);
}

void MainWindow::addExternalSubtitle()
{
    QString file = QFileDialog::getOpenFileName(this, "Add External Subtitle", "", "Subtitles (*.srt *.ass *.ssa *.sub *.vtt *.sup)");
    if (!file.isEmpty()) {
        m_mpvWidget->command(QVariantList() << "sub-add" << QDir::toNativeSeparators(file));
    }
}

void MainWindow::addExternalAudio()
{
    QString file = QFileDialog::getOpenFileName(this, "Add External Audio", "", "Audio (*.mp3 *.m4a *.aac *.flac *.wav *.ac3 *.dts)");
    if (!file.isEmpty()) {
        m_mpvWidget->command(QVariantList() << "audio-add" << QDir::toNativeSeparators(file));
    }
}

void MainWindow::onUrlClicked()
{
    if (m_urlEdit) {
        bool visible = !m_urlEdit->isVisible();
        m_urlEdit->setVisible(visible);
        if (visible) {
            m_urlEdit->setFocus();
            m_urlEdit->selectAll();
        }
    }
}

void MainWindow::onUrlSubmitted()
{
    if (m_urlEdit) {
        QString url = m_urlEdit->text().trimmed();
        if (!url.isEmpty()) {
            openFile(url);
            m_urlEdit->clear();
            m_urlEdit->hide();
        }
    }
}

void MainWindow::onFullscreenClicked() { toggleFullscreen(); }

void MainWindow::onBrightnessChanged(int level)
{
    if (m_syncingFromSystem) return;
    
    const float brightnessLevel = qBound(0, level, 100) / 100.0f;
    WinOSIntegration::instance().setSystemBrightness(brightnessLevel);
}

void MainWindow::updateHoverBars()
{
    if (QApplication::activePopupWidget() || QApplication::activeModalWidget()) return;
    if (!m_mpvWidget) return;
    
    // Protect sliders while actively dragging (avoid getting stuck)
    bool draggingLeft = m_brightnessSlider && m_brightnessSlider->isSliderDown();
    bool draggingRight = m_volumeHoverSlider && m_volumeHoverSlider->isSliderDown();
    
    auto localPos = m_mpvWidget->mapFromGlobal(QCursor::pos());

    if (!draggingLeft && !draggingRight && !m_mpvWidget->rect().contains(localPos)) {
        m_brightnessBar->hide();
        m_volumeBar->hide();
        return;
    }

    int mw = m_mpvWidget->width();
    bool inLeftZone = draggingLeft || (localPos.x() < mw * 0.10) || m_brightnessBar->geometry().contains(localPos);
    bool inRightZone = draggingRight || (localPos.x() > mw * 0.90) || m_volumeBar->geometry().contains(localPos);

    m_brightnessBar->setVisible(inLeftZone);
    m_volumeBar->setVisible(inRightZone);
}

void MainWindow::updateResolutionBadge()
{
    if (!m_resolutionBadge || !m_mpvWidget) return;

    int vw = m_mpvWidget->getProperty("video-params/w").toInt();
    int vh = m_mpvWidget->getProperty("video-params/h").toInt();
    if (vw <= 0 || vh <= 0) {
        m_resolutionBadge->hide();
        return;
    }

    // Determine viewport size
    int viewportW = m_mpvWidget->width();
    int viewportH = m_mpvWidget->height();

    // Helper to format resolution name (parity with macOS formatResolution)
    auto formatResolution = [](int w, int h) -> QString {
        struct Res { QString name; int w; int h; };
        static const Res standards[] = {
            {"4K", 3840, 2160},
            {"1600p", 2560, 1600},
            {"1440p", 2560, 1440},
            {"1200p", 1920, 1200},
            {"1080p", 1920, 1080},
            {"900p", 1600, 900},
            {"768p", 1024, 768},
            {"720p", 1280, 720},
            {"576p", 1024, 576},
            {"540p", 960, 540},
            {"480p", 854, 480},
            {"360p", 640, 360}
        };

        for (const auto& std : standards) {
            double hDiff = qAbs(static_cast<double>(h - std.h)) / std.h;
            double wDiff = qAbs(static_cast<double>(w - std.w)) / std.w;
            if (hDiff <= 0.03 || wDiff <= 0.03) {
                return std.name;
            }
        }
        return QString("%1p").arg(h);
    };

    QString originalName = formatResolution(vw, vh);

    // Check if we are upscaling (viewport size larger than original size)
    bool isUpscaling = (viewportW > vw) || (viewportH > vh);

    if (isUpscaling) {
        QString upscaledName = formatResolution(viewportW, viewportH);
        m_resolutionBadge->setText(QString("%1 ➔ %2").arg(originalName, upscaledName));
        // Style with soft blue tint to indicate active enhancement/upscaling
        m_resolutionBadge->setStyleSheet(
            "QLabel#resolutionBadge { "
            "  background-color: rgba(25, 118, 210, 0.25); " // soft blue tint
            "  color: #60CDFF; " // accent blue text
            "  border-radius: 4px; "
            "  padding: 2px 6px; "
            "  font-size: 11px; "
            "  font-weight: bold; "
            "}"
        );
    } else {
        m_resolutionBadge->setText(originalName);
        m_resolutionBadge->setStyleSheet(
            "QLabel#resolutionBadge { "
            "  background-color: rgba(255, 255, 255, 0.15); "
            "  color: white; "
            "  border-radius: 4px; "
            "  padding: 2px 6px; "
            "  font-size: 11px; "
            "  font-weight: bold; "
            "}"
        );
    }

    m_resolutionBadge->show();
}

void MainWindow::applyScrollDelta(int delta, double xPos)
{
    const int mw = m_mpvWidget ? m_mpvWidget->width() : width();
    if (xPos < mw * 0.1) {
        m_brightnessSlider->setValue(qBound(0, m_brightnessSlider->value() + delta, 100));
    } else {
        onVolumeChanged(qBound(0, m_volumeSlider->value() + delta, 100));
    }
    showHud();
    updateHoverBars();
}

void MainWindow::mouseMoveEvent(QMouseEvent *event)
{
    showHud();
    updateHoverBars();
    QMainWindow::mouseMoveEvent(event);
}

void MainWindow::wheelEvent(QWheelEvent *event)
{
    applyScrollDelta(event->angleDelta().y() > 0 ? 5 : -5, event->position().x());
    event->accept();
}

void MainWindow::mouseDoubleClickEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton) {
        auto localPos = event->pos();
        if (!m_topBar->geometry().contains(localPos) && !m_bottomBar->geometry().contains(localPos)) {
            toggleFullscreen();
            event->accept();
            return;
        }
    }
    QMainWindow::mouseDoubleClickEvent(event);
}

bool MainWindow::eventFilter(QObject *watched, QEvent *event)
{
    if (QApplication::activePopupWidget() || QApplication::activeModalWidget()) {
        return QMainWindow::eventFilter(watched, event);
    }

    if (watched == m_seekSlider) {
        if (event->type() == QEvent::MouseMove) {
            QMouseEvent *mouseEvent = static_cast<QMouseEvent*>(event);
            handleTimelineHover(mouseEvent->pos());
        } else if (event->type() == QEvent::Leave) {
            hideTimelinePreview();
        }
    }
    if (watched == m_mpvWidget) {
        if (event->type() == QEvent::Resize) {
            updateHudPositions();
        } else if (event->type() == QEvent::MouseButtonPress) {
            auto *mouseEvent = static_cast<QMouseEvent*>(event);
            if (mouseEvent->button() == Qt::LeftButton) {
                QPoint localPos = mouseEvent->pos();
                if ((m_topBar->isVisible() && m_topBar->geometry().contains(localPos)) ||
                    (m_bottomBar->isVisible() && m_bottomBar->geometry().contains(localPos)) ||
                    (m_brightnessBar->isVisible() && m_brightnessBar->geometry().contains(localPos)) ||
                    (m_volumeBar->isVisible() && m_volumeBar->geometry().contains(localPos))) {
                    return false;
                }
                
                qint64 now = QDateTime::currentMSecsSinceEpoch();
                if (now - m_lastClickTime < QGuiApplication::styleHints()->mouseDoubleClickInterval()) {
                    m_clickTimer->stop();
                    toggleFullscreen();
                    m_lastClickTime = 0;
                } else {
                    m_lastClickTime = now;
                    m_clickTimer->start();
                }
                return true;
            }
        } else if (event->type() == QEvent::Wheel) {
            auto *wheelEvent = static_cast<QWheelEvent*>(event);
            applyScrollDelta(wheelEvent->angleDelta().y() > 0 ? 5 : -5, wheelEvent->position().x());
            return true;
        } else if (event->type() == QEvent::MouseMove) {
            showHud();
            updateHoverBars();
        } else if (event->type() == QEvent::Leave) {
            updateHoverBars();
        }
    }
    return QMainWindow::eventFilter(watched, event);
}

void MainWindow::showHud()
{
    m_topBar->show();
    m_bottomBar->show();
    
    unsetCursor();
    m_mpvWidget->unsetCursor();
    
    QString autohide = m_settings.value("cursorAutohide", "3000").toString();
    if (autohide == "never") {
        m_hudTimer->stop();
    } else {
        m_hudTimer->start(autohide.toInt());
    }
}

void MainWindow::hideHud()
{
    if (QApplication::activePopupWidget() || QApplication::activeModalWidget()) return;
    
    m_topBar->hide();
    m_bottomBar->hide();
    m_brightnessBar->hide();
    m_volumeBar->hide();
    
    setCursor(Qt::BlankCursor);
    m_mpvWidget->setCursor(Qt::BlankCursor);
}

void MainWindow::updateVolumeIcon(int volume, bool muted)
{
    if (muted || volume <= 0) {
        m_volumeBtn->setIcon(QIcon(":/icons/volume_mute.svg"));
    } else if (volume < 50) {
        m_volumeBtn->setIcon(QIcon(":/icons/volume_mid.svg"));
    } else {
        m_volumeBtn->setIcon(QIcon(":/icons/volume_high.svg"));
    }
}

void MainWindow::syncSystemControls()
{
    const float sysVolume = WinOSIntegration::instance().getSystemVolume();
    const int volumeValue = qRound(sysVolume * 100.0f);
    
    static int lastSystemVolume = -1;
    bool systemVolumeChanged = (lastSystemVolume != volumeValue);
    lastSystemVolume = volumeValue;
    
    const bool muted = WinOSIntegration::instance().isMuted() || volumeValue == 0;

    const float sysBrightness = WinOSIntegration::instance().getSystemBrightness();
    const int brightnessValue = qRound(sysBrightness * 100.0f);

    m_syncingFromSystem = true;
    {
        QSignalBlocker mainBlocker(m_volumeSlider);
        if (m_volumeSlider->value() <= 100 || systemVolumeChanged) {
            if (m_volumeSlider->value() != volumeValue) {
                m_volumeSlider->setValue(volumeValue);
            }
        }
    }
    {
        QSignalBlocker hoverBlocker(m_volumeHoverSlider);
        if (m_volumeHoverSlider->value() != volumeValue) {
            m_volumeHoverSlider->setValue(volumeValue);
        }
    }
    {
        QSignalBlocker brightnessBlocker(m_brightnessSlider);
        if (m_brightnessSlider->value() != brightnessValue) {
            m_brightnessSlider->setValue(brightnessValue);
        }
    }
    m_syncingFromSystem = false;

    // Keep internal mpv player volume in sync
    if (m_volumeSlider->value() <= 100 || systemVolumeChanged) {
        if (m_mpvWidget->getProperty("volume").toInt() != volumeValue)
            m_mpvWidget->setVolume(volumeValue);
    }

    if (!m_volumeSlider->isSliderDown()) {
        m_isMuted = muted;
        updateVolumeIcon(m_volumeSlider->value(), muted);
    }
}

void MainWindow::toggleFullscreen()
{
    if (isFullScreen()) {
        showNormal();
        m_fullscreenBtn->setIcon(QIcon(":/icons/fullscreen.svg"));
    } else {
        showFullScreen();
        m_fullscreenBtn->setIcon(QIcon(":/icons/fullscreen_exit.svg"));
    }
    updateHudPositions();
}

void MainWindow::keyPressEvent(QKeyEvent *event)
{
    QMainWindow::keyPressEvent(event);
}

void MainWindow::executeCommand(const QString &commandLine)
{
    QStringList args;
    QString current;
    bool inQuotes = false;
    for (int i = 0; i < commandLine.length(); ++i) {
        QChar c = commandLine[i];
        if (c == '"') {
            inQuotes = !inQuotes;
        } else if (c == ' ' && !inQuotes) {
            if (!current.isEmpty()) {
                args << current;
                current.clear();
            }
        } else {
            current.append(c);
        }
    }
    if (!current.isEmpty()) {
        args << current;
    }

    if (args.isEmpty()) return;

    QString cmd = args.first().toLower();
    args.removeFirst();

    // Fallback: if cmd is not a known command, treat the entire commandLine as a path to load
    if (cmd != "play" && cmd != "pause" && cmd != "toggle" && cmd != "stop" && cmd != "seek" &&
        cmd != "volume" && cmd != "mute" && cmd != "load" && cmd != "anime4k" && cmd != "fullscreen" &&
        cmd != "speed" && cmd != "aspect" && cmd != "next" && cmd != "prev") {
        
        suppressWelcome();
        if (m_welcomeWindow && m_welcomeWindow->isVisible()) {
            m_welcomeWindow->accept();
        }
        openFile(commandLine);
        show();
        raise();
        activateWindow();
        return;
    }

    if (cmd == "play") {
        m_mpvWidget->play();
    } else if (cmd == "pause") {
        m_mpvWidget->pause();
    } else if (cmd == "toggle") {
        onPlayPauseClicked();
    } else if (cmd == "stop") {
        m_mpvWidget->pause();
        m_mpvWidget->setProperty("time-pos", 0);
    } else if (cmd == "seek") {
        if (!args.isEmpty()) {
            double offset = args.first().toDouble();
            m_mpvWidget->seek(offset);
        }
    } else if (cmd == "volume") {
        if (!args.isEmpty()) {
            int vol = args.first().toInt();
            onVolumeChanged(vol);
        }
    } else if (cmd == "mute") {
        onMuteClicked();
    } else if (cmd == "load") {
        if (!args.isEmpty()) {
            suppressWelcome();
            openFile(args.first());
            show();
            raise();
            activateWindow();
        }
    } else if (cmd == "anime4k") {
        if (!args.isEmpty()) {
            setAnime4kPreset(args.first());
        }
    } else if (cmd == "fullscreen") {
        toggleFullscreen();
    } else if (cmd == "speed") {
        if (!args.isEmpty()) {
            double val = args.first().toDouble();
            m_mpvWidget->setProperty("speed", val);
            m_speedBtn->setText(val == (int)val ? QString::number((int)val) + "x" : QString::number(val) + "x");
        }
    } else if (cmd == "aspect") {
        if (!args.isEmpty()) {
            QString aspect = args.first();
            if (aspect == "auto") {
                m_mpvWidget->setProperty("video-aspect-override", "-1");
            } else {
                m_mpvWidget->setProperty("video-aspect-override", aspect);
            }
        }
    } else if (cmd == "next") {
        onNextClicked();
    } else if (cmd == "prev") {
        onPrevClicked();
    }
}

QList<MainWindow::ShortcutInfo> MainWindow::getShortcutDefinitions()
{
    return {
        {"PlayPause", "Play / Pause", "Space"},
        {"Fullscreen", "Toggle Fullscreen", "F"},
        {"SeekBackward", "Seek Backward 5s", "Left"},
        {"SeekForward", "Seek Forward 5s", "Right"},
        {"VolumeUp", "Volume Up", "Up"},
        {"VolumeDown", "Volume Down", "Down"},
        {"Mute", "Mute / Unmute", "M"},
        {"BrightnessUp", "Brightness Up", "Ctrl+Up"},
        {"BrightnessDown", "Brightness Down", "Ctrl+Down"},
        {"SubtitleCycle", "Cycle Subtitle Track", "S"},
        {"AudioCycle", "Cycle Audio Track", "Ctrl+A"},
        {"AspectCycle", "Cycle Aspect Ratio", "Shift+A"},
        {"ShaderCycle", "Toggle/Cycle Anime4K", "Ctrl+K"},
        {"OpenFile", "Open File", "Ctrl+O"},
        {"OpenUrl", "Open URL", "Ctrl+U"},
        {"OpenSettings", "Open Settings Window", "Ctrl+,"},
        {"AudioDelayIncrease", "Audio Delay Increase (1ms)", "Ctrl+]"},
        {"AudioDelayDecrease", "Audio Delay Decrease (1ms)", "Ctrl+["},
        {"Escape", "Exit Fullscreen", "Escape"},
        {"SeekBackward10", "Seek Backward 10s", "J"},
        {"SeekForward10", "Seek Forward 10s", "L"},
        {"FrameStep", "Frame Step Forward", "."},
        {"FrameBackStep", "Frame Step Backward", ","},
        {"SpeedUp", "Speed Up (+0.25x)", "]"},
        {"SpeedDown", "Speed Down (-0.25x)", "["},
        {"VideoInfo", "Toggle Video Info", "I"},
        {"PlayPauseK", "Play/Pause (Alt)", "K"},
        {"AudioDelayUp", "Audio Delay +100ms", ";"},
        {"AudioDelayDown", "Audio Delay -100ms", "'"},
        {"AudioDelayReset", "Reset Audio Delay", "\\"}
    };
}

void MainWindow::handleShortcutTrigger(const QString &action)
{
    if (action == "PlayPause" || action == "PlayPauseK") {
        onPlayPauseClicked();
    } else if (action == "Fullscreen") {
        toggleFullscreen();
    } else if (action == "Escape") {
        if (isFullScreen()) {
            toggleFullscreen();
        }
    } else if (action == "SeekBackward") {
        m_mpvWidget->seek(-5.0);
    } else if (action == "SeekForward") {
        m_mpvWidget->seek(5.0);
    } else if (action == "SeekBackward10") {
        m_mpvWidget->seek(-10.0);
    } else if (action == "SeekForward10") {
        m_mpvWidget->seek(10.0);
    } else if (action == "FrameStep") {
        m_mpvWidget->command(QVariantList() << "frame-step");
    } else if (action == "FrameBackStep") {
        m_mpvWidget->command(QVariantList() << "frame-back-step");
    } else if (action == "SpeedUp") {
        double currentSpeed = m_mpvWidget->getProperty("speed").toDouble();
        double nextSpeed = qBound(0.25, currentSpeed + 0.25, 4.0);
        m_mpvWidget->setProperty("speed", nextSpeed);
        m_mpvWidget->command(QVariantList() << "show-text" << QString("Speed: %1x").arg(nextSpeed, 0, 'f', 2));
        if (m_speedBtn) {
            m_speedBtn->setText(nextSpeed == static_cast<int>(nextSpeed)
                ? QString::number(static_cast<int>(nextSpeed)) + "x"
                : QString::number(nextSpeed, 'f', 2) + "x");
        }
    } else if (action == "SpeedDown") {
        double currentSpeed = m_mpvWidget->getProperty("speed").toDouble();
        double nextSpeed = qBound(0.25, currentSpeed - 0.25, 4.0);
        m_mpvWidget->setProperty("speed", nextSpeed);
        m_mpvWidget->command(QVariantList() << "show-text" << QString("Speed: %1x").arg(nextSpeed, 0, 'f', 2));
        if (m_speedBtn) {
            m_speedBtn->setText(nextSpeed == static_cast<int>(nextSpeed)
                ? QString::number(static_cast<int>(nextSpeed)) + "x"
                : QString::number(nextSpeed, 'f', 2) + "x");
        }
    } else if (action == "VideoInfo") {
        m_mpvWidget->command(QVariantList() << "script-binding" << "stats/display-stats-toggle");
    } else if (action == "VolumeUp") {
        int newVolume = qBound(0, m_volumeSlider->value() + 5, 200);
        m_volumeSlider->setValue(newVolume);
    } else if (action == "VolumeDown") {
        int newVolume = qBound(0, m_volumeSlider->value() - 5, 200);
        m_volumeSlider->setValue(newVolume);
    } else if (action == "Mute") {
        onMuteClicked();
    } else if (action == "BrightnessUp") {
        int newBright = qBound(0, m_brightnessSlider->value() + 5, 100);
        m_brightnessSlider->setValue(newBright);
    } else if (action == "BrightnessDown") {
        int newBright = qBound(0, m_brightnessSlider->value() - 5, 100);
        m_brightnessSlider->setValue(newBright);
    } else if (action == "SubtitleCycle") {
        cycleSubtitleTrack();
    } else if (action == "AudioCycle") {
        cycleAudioTrack();
    } else if (action == "AspectCycle") {
        cycleAspectOverride();
    } else if (action == "ShaderCycle") {
        cycleShaderPreset();
    } else if (action == "OpenFile") {
        onOpenClicked();
    } else if (action == "OpenUrl") {
        onUrlClicked();
    } else if (action == "OpenSettings") {
        onSettingsClicked();
    } else if (action == "AudioDelayIncrease") {
        adjustAudioDelay(0.001);
    } else if (action == "AudioDelayDecrease") {
        adjustAudioDelay(-0.001);
    } else if (action == "AudioDelayUp") {
        adjustAudioDelay(0.100);
    } else if (action == "AudioDelayDown") {
        adjustAudioDelay(-0.100);
    } else if (action == "AudioDelayReset") {
        m_mpvWidget->setProperty("audio-delay", 0.0);
        m_mpvWidget->command(QVariantList() << "show-text" << "Audio Delay: 0 ms");
    }
}

void MainWindow::cycleSubtitleTrack()
{
    QList<TrackInfo> subTracks;
    for (const auto& track : getTracks()) {
        if (track.type == "sub") subTracks << track;
    }
    if (subTracks.isEmpty()) return;

    int activeId = -1;
    for (const auto& track : subTracks) {
        if (track.selected) activeId = track.id;
    }

    int nextIndex = -1;
    for (int i = 0; i < subTracks.size(); ++i) {
        if (subTracks[i].id == activeId) {
            nextIndex = (i + 1) % (subTracks.size() + 1); // include Off
            break;
        }
    }
    if (nextIndex == -1) nextIndex = 0;

    if (nextIndex == subTracks.size()) {
        setSubtitleTrack(-1);
        m_mpvWidget->command(QVariantList() << "show-text" << "Subtitles: Off");
    } else {
        setSubtitleTrack(subTracks[nextIndex].id);
        m_mpvWidget->command(QVariantList() << "show-text" << QString("Subtitle Track: %1").arg(subTracks[nextIndex].label));
    }
}

void MainWindow::cycleAudioTrack()
{
    QList<TrackInfo> audioTracks;
    for (const auto& track : getTracks()) {
        if (track.type == "audio") audioTracks << track;
    }
    if (audioTracks.isEmpty()) return;

    int activeId = -1;
    for (const auto& track : audioTracks) {
        if (track.selected) activeId = track.id;
    }

    int nextIndex = 0;
    for (int i = 0; i < audioTracks.size(); ++i) {
        if (audioTracks[i].id == activeId) {
            nextIndex = (i + 1) % audioTracks.size();
            break;
        }
    }

    setAudioTrack(audioTracks[nextIndex].id);
    m_mpvWidget->command(QVariantList() << "show-text" << QString("Audio Track: %1").arg(audioTracks[nextIndex].label));
}

void MainWindow::cycleAspectOverride()
{
    QString currentAspect = m_mpvWidget->getProperty("video-aspect-override").toString();
    QStringList order = {"-1", "16:9", "16:10", "4:3", "21:9", "2.35:1"};
    QStringList labels = {"Auto", "16:9", "16:10", "4:3", "21:9", "2.35:1"};
    
    int idx = order.indexOf(currentAspect);
    if (idx == -1 && currentAspect.toDouble() <= 0) idx = 0;
    int nextIdx = (idx + 1) % order.size();
    
    m_mpvWidget->setProperty("video-aspect-override", order[nextIdx]);
    m_mpvWidget->command(QVariantList() << "show-text" << QString("Aspect Ratio: %1").arg(labels[nextIdx]));
}

void MainWindow::cycleShaderPreset()
{
    QString currentPreset = m_settings.value("defaultShaderPreset", "Off").toString();
    QStringList presets = {"Off", "Mode A (HQ)", "Mode B (HQ)", "Mode C (HQ)",
                           "Mode A (Fast)", "Mode B (Fast)", "Mode C (Fast)"};
    
    int idx = presets.indexOf(currentPreset);
    if (idx == -1) idx = 0;
    int nextIdx = (idx + 1) % presets.size();
    
    applySettingToMpv("defaultShaderPreset", presets[nextIdx]);
    m_settings.setValue("defaultShaderPreset", presets[nextIdx]);
    m_mpvWidget->command(QVariantList() << "show-text" << QString("Anime4K Shader: %1").arg(presets[nextIdx]));
}

void MainWindow::adjustAudioDelay(double deltaSeconds)
{
    double currentDelay = m_mpvWidget->getProperty("audio-delay").toDouble();
    double newDelay = currentDelay + deltaSeconds;
    m_mpvWidget->setProperty("audio-delay", newDelay);
    m_mpvWidget->command(QVariantList() << "show-text" << QString("Audio Delay: %1 ms").arg(qRound(newDelay * 1000.0)));
}

void MainWindow::handleTimelineHover(QPoint pos)
{
    if (m_duration <= 0) return;

    int val = m_seekSlider->style()->sliderValueFromPosition(
        m_seekSlider->minimum(),
        m_seekSlider->maximum(),
        pos.x(),
        m_seekSlider->width()
    );
    double time = (static_cast<double>(val) / m_seekSlider->maximum()) * m_duration;
    m_lastHoverTime = time;

    bool isNewHover = false;
    if (!m_previewWidget) {
        m_previewWidget = new TimelinePreviewWidget(m_mpvWidget);
        isNewHover = true;
    } else if (!m_previewWidget->isVisible()) {
        isNewHover = true;
    }

    QPoint globalPos = m_seekSlider->mapTo(m_mpvWidget, QPoint(pos.x(), 0));
    int x = globalPos.x() - m_previewWidget->width() / 2;
    x = qBound(16, x, m_mpvWidget->width() - m_previewWidget->width() - 16);
    int y = m_bottomBar->y() - m_previewWidget->height() - 8;
    m_previewWidget->move(x, y);
    m_previewWidget->show();
    m_previewWidget->raise();

    int halfSec = static_cast<int>(time * 2);
    if (m_thumbnailCache.contains(halfSec)) {
        m_previewWidget->setPreview(m_thumbnailCache.value(halfSec), formatTime(time));
    } else {
        m_previewWidget->setPreview(QImage(), formatTime(time), !isNewHover);
        generateThumbnail(time, halfSec);
    }
}

void MainWindow::hideTimelinePreview()
{
    if (m_previewWidget) {
        m_previewWidget->hide();
    }
}

void MainWindow::generateThumbnail(double time, int cacheKey)
{
    if (m_isGeneratingThumbnail) {
        m_pendingThumbnailTime = time;
        return;
    }
    m_isGeneratingThumbnail = true;

    m_thumbnailMpv->requestThumbnail(time, cacheKey, this, [this](QImage img, int key) {
        if (!img.isNull()) {
            if (m_thumbnailCache.size() > 500) {
                m_thumbnailCache.clear();
            }
            m_thumbnailCache.insert(key, img);
            if (m_previewWidget && m_previewWidget->isVisible()) {
                m_previewWidget->setPreview(img, formatTime(m_lastHoverTime));
            }
        }
        m_isGeneratingThumbnail = false;

        if (m_pendingThumbnailTime >= 0) {
            double pending = m_pendingThumbnailTime;
            m_pendingThumbnailTime = -1;
            generateThumbnail(pending, static_cast<int>(pending * 2));
        }
    });
}

