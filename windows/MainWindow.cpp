#include "MainWindow.h"
#include "WinOSIntegration.h"
#include <QFileDialog>
#include <QKeyEvent>
#include <QFile>
#include <QTemporaryDir>
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
#include <QStyleHints>
#include <QScreen>
#include <algorithm>
#include <thread>
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
            "QWidget { "
            "  background-color: rgba(30, 30, 30, 230); "
            "  border: 1px solid rgba(255, 255, 255, 40); "
            "  border-radius: 8px; "
            "}"
        );

        m_imgLabel = new QLabel(this);
        m_imgLabel->setGeometry(4, 4, 172, 94); // fit beautifully inside
        m_imgLabel->setStyleSheet("background-color: rgba(0, 0, 0, 80); border-radius: 4px; border: none;");
        m_imgLabel->setScaledContents(true);

        m_timeLabel = new QLabel(this);
        m_timeLabel->setGeometry(0, 100, 180, 18);
        m_timeLabel->setAlignment(Qt::AlignCenter);
        m_timeLabel->setStyleSheet("color: white; font-family: monospace; font-size: 11px; font-weight: bold; background: transparent; border: none;");
        
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
    ThumbnailMpv() {
        m_tmpPath = QDir::tempPath() + QString("/glassplayer_thumb_%1.jpg").arg(QCoreApplication::applicationPid());
        setupMpv();
    }
    ~ThumbnailMpv() {
        shutdown();
    }

    void shutdown() {
        if (m_mpv) {
            mpv_terminate_destroy(m_mpv);
            m_mpv = nullptr;
        }
        QFile::remove(m_tmpPath);
        m_currentFile.clear();
    }

    void loadSource(const QString &source) {
        if (!m_mpv) setupMpv();
        if (!m_mpv || source == m_currentFile) return;
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
            mpv_event *event = mpv_wait_event(m_mpv, 0.05);
            if (!event || event->event_id == MPV_EVENT_NONE) continue;
            if (event->event_id == MPV_EVENT_FILE_LOADED) break;
        }
    }

    QImage generateThumbnail(double time) {
        if (!m_mpv) return QImage();

        QString seekCmd = QString("seek %1 absolute+keyframes").arg(time);
        mpv_command_string(m_mpv, seekCmd.toUtf8().constData());

        for (int i = 0; i < 15; ++i) {
            mpv_event *event = mpv_wait_event(m_mpv, 0.002);
            if (!event || event->event_id == MPV_EVENT_NONE) break;
            if (event->event_id == MPV_EVENT_PLAYBACK_RESTART) break;
        }

        QByteArray tmpPathBytes = QDir::toNativeSeparators(m_tmpPath).toUtf8();
        const char *screenshotCmd[] = {"screenshot-to-file", tmpPathBytes.constData(), "video", nullptr};
        mpv_command(m_mpv, screenshotCmd);

        QImage result;
        for (int attempt = 0; attempt < 4; ++attempt) {
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
        return result;
    }

private:
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
};


static const QString kMenuStyle = QStringLiteral(
    "QMenu { "
    "  background-color: rgba(30, 30, 30, 230); "
    "  color: white; "
    "  border: 1px solid rgba(255, 255, 255, 40); "
    "  border-radius: 8px; "
    "  padding: 4px 0px; "
    "}"
    "QMenu::item { "
    "  padding: 6px 20px 6px 25px; "
    "  margin: 2px 6px; "
    "  border-radius: 4px; "
    "  font-size: 13px; "
    "}"
    "QMenu::item:selected { "
    "  background-color: rgba(255, 255, 255, 30); "
    "}"
    "QMenu::separator { "
    "  height: 1px; "
    "  background: rgba(255, 255, 255, 25); "
    "  margin: 4px 0px; "
    "}"
);

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent), m_settings("GlassPlayer", "Settings")
{
    setupUi();

    connect(m_mpvWidget, &MpvWidget::positionChanged, this, &MainWindow::updatePosition);
    connect(m_mpvWidget, &MpvWidget::durationChanged, this, &MainWindow::updateDuration);
    connect(m_mpvWidget, &MpvWidget::fileLoaded, this, &MainWindow::onFileLoaded);
    connect(m_brightnessSlider, &QSlider::sliderReleased, this, &MainWindow::updateHoverBars);
    connect(m_volumeHoverSlider, &QSlider::sliderReleased, this, &MainWindow::updateHoverBars);
    connect(m_mpvWidget, &MpvWidget::pauseChanged, this, [this](bool paused) {
        m_isPlaying = !paused;
        m_playPauseBtn->setIcon(QIcon(paused ? ":/icons/play.svg" : ":/icons/pause.svg"));
        if (!paused) {
            hideHud();
        } else {
            showHud();
        }
    });
    
    const int initialSystemVolume = qRound(WinOSIntegration::instance().getSystemVolume() * 100.0f);
    m_volumeSlider->setValue(initialSystemVolume);
    syncSystemControls();
    
    connect(m_mpvWidget, &MpvWidget::eofReached, this, [this](){
        m_isPlaying = false;
        m_playPauseBtn->setIcon(QIcon(":/icons/play.svg"));
    });

    m_welcomeWindow = new WelcomeWindow(this);
    connect(m_welcomeWindow, &WelcomeWindow::fileOpened, this, &MainWindow::openFile);
    connect(m_welcomeWindow, &WelcomeWindow::openRcloneBrowser, this, &MainWindow::onRcloneClicked);

    m_settingsWindow = new SettingsWindow(this);
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
    m_systemSyncTimer->start();

    setMouseTracking(true);
    centralWidget()->setMouseTracking(true);
    m_mpvWidget->setMouseTracking(true);
    m_mpvWidget->installEventFilter(this);
    m_rcloneBrowser = new RcloneBrowser(this);
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
        m_settings.setValue("windowResize", "Never resize");
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
    if (m_thumbnailMpv) {
        m_thumbnailMpv->shutdown();
        delete m_thumbnailMpv;
    }
}

void MainWindow::suppressWelcome()
{
    m_welcomeSuppressed = true;
}

void MainWindow::setupUi()
{
    setWindowTitle("Glass Player");
    resize(1280, 720);
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
        "QWidget#topBar { "
        "  background-color: rgba(30, 30, 30, 180); "
        "  border-bottom-left-radius: 0px; "
        "  border-bottom-right-radius: 0px; "
        "}"
        "QPushButton { "
        "  background: transparent; color: white; border: none; font-size: 16px; padding: 5px; "
        "}"
        "QPushButton:hover { color: #aaa; }"
        "QLabel { color: white; font-weight: 500; font-size: 13px; }"
    );

    QHBoxLayout *layout = new QHBoxLayout(m_topBar);
    layout->setContentsMargins(15, 0, 15, 0);

    m_urlEdit = new QLineEdit(m_topBar);
    m_urlEdit->setPlaceholderText("Paste URL (YouTube, HTTP, etc.)");
    m_urlEdit->setStyleSheet(
        "QLineEdit { "
        "  background: rgba(255, 255, 255, 20); "
        "  color: white; "
        "  border: 1px solid rgba(255, 255, 255, 40); "
        "  border-radius: 6px; "
        "  padding: 4px 10px; "
        "  font-size: 13px; "
        "}"
        "QLineEdit:focus { "
        "  border: 1px solid #0078d4; "
        "}"
    );
    m_urlEdit->setFixedWidth(350);
    m_urlEdit->hide();
    connect(m_urlEdit, &QLineEdit::returnPressed, this, &MainWindow::onUrlSubmitted);

    layout->addStretch();
    layout->addWidget(m_urlEdit);

    QPushButton *urlBtn = new QPushButton(m_topBar);
    urlBtn->setIcon(QIcon(":/icons/url.svg"));
    urlBtn->setIconSize(QSize(20, 20));
    connect(urlBtn, &QPushButton::clicked, this, &MainWindow::onUrlClicked);
    layout->addWidget(urlBtn);

    QPushButton *openBtn = new QPushButton(m_topBar);
    openBtn->setIcon(QIcon(":/icons/open_file.svg"));
    openBtn->setIconSize(QSize(20, 20));
    connect(openBtn, &QPushButton::clicked, this, &MainWindow::onOpenClicked);
    layout->addWidget(openBtn);

    QPushButton *remoteBtn = new QPushButton(m_topBar);
    remoteBtn->setIcon(QIcon(":/icons/remote.svg"));
    remoteBtn->setIconSize(QSize(20, 20));
    connect(remoteBtn, &QPushButton::clicked, this, &MainWindow::onRcloneClicked);
    layout->addWidget(remoteBtn);

    QPushButton *settingsBtn = new QPushButton(m_topBar);
    settingsBtn->setIcon(QIcon(":/icons/settings.svg"));
    settingsBtn->setIconSize(QSize(20, 20));
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
        "QWidget#bottomBar { "
        "  background-color: rgba(30, 30, 30, 180); "
        "  border-radius: 12px; "
        "}"
        "QPushButton { "
        "  background: transparent; color: white; border: none; font-size: 18px; min-width: 30px; "
        "}"
        "QPushButton#playPause { "
        "  background: rgba(255, 255, 255, 40); border-radius: 20px; min-width: 40px; min-height: 40px; font-size: 20px; "
        "}"
        "QPushButton:hover { background: rgba(255, 255, 255, 20); }"
        "QLabel { color: white; font-size: 11px; font-family: 'Segoe UI', sans-serif; }"
        "QSlider::horizontal { height: 16px; background: transparent; }"
        "QSlider::groove:horizontal { height: 4px; background: rgba(255, 255, 255, 50); border-radius: 2px; }"
        "QSlider::handle:horizontal { width: 12px; height: 12px; background: white; margin-top: -4px; margin-bottom: -4px; border-radius: 6px; border: none; }"
        "QSlider::sub-page:horizontal { background: white; border-radius: 2px; }"
    );

    m_currentTimeLabel = new QLabel("0:00", m_bottomBar);
    m_currentTimeLabel->setFixedWidth(60);

    m_seekSlider = new ClickableSlider(Qt::Horizontal, m_bottomBar);
    m_seekSlider->setRange(0, 1000);
    m_seekSlider->setMouseTracking(true);
    m_seekSlider->installEventFilter(this);
    connect(m_seekSlider, &QSlider::sliderMoved, this, &MainWindow::onSliderMoved);
    connect(m_seekSlider, &QSlider::sliderReleased, this, &MainWindow::onSliderReleased);

    m_remainingTimeLabel = new QLabel("-0:00", m_bottomBar);
    m_remainingTimeLabel->setFixedWidth(60);
    m_remainingTimeLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);

    m_subtitleBtn = new QPushButton(m_bottomBar);
    m_subtitleBtn->setIcon(QIcon(":/icons/subtitle.svg"));
    connect(m_subtitleBtn, &QPushButton::clicked, this, &MainWindow::onSubtitleClicked);

    m_audioBtn = new QPushButton(m_bottomBar);
    m_audioBtn->setIcon(QIcon(":/icons/audio.svg"));
    connect(m_audioBtn, &QPushButton::clicked, this, &MainWindow::onAudioClicked);

    m_shaderBtn = new QPushButton(m_bottomBar);
    m_shaderBtn->setIcon(QIcon(":/icons/shader.svg"));
    connect(m_shaderBtn, &QPushButton::clicked, this, &MainWindow::onShaderClicked);

    m_rewindBtn = new QPushButton(m_bottomBar);
    m_rewindBtn->setIcon(QIcon(":/icons/rewind.svg"));
    m_prevBtn = new QPushButton(m_bottomBar);
    m_prevBtn->setIcon(QIcon(":/icons/prev.svg"));
    m_playPauseBtn = new QPushButton(m_bottomBar);
    m_playPauseBtn->setIcon(QIcon(":/icons/pause.svg"));
    m_playPauseBtn->setObjectName("playPause");
    m_playPauseBtn->setIconSize(QSize(24, 24));
    m_nextBtn = new QPushButton(m_bottomBar);
    m_nextBtn->setIcon(QIcon(":/icons/next.svg"));
    m_forwardBtn = new QPushButton(m_bottomBar);
    m_forwardBtn->setIcon(QIcon(":/icons/forward.svg"));

    connect(m_rewindBtn, &QPushButton::clicked, this, &MainWindow::onRewindClicked);
    connect(m_prevBtn, &QPushButton::clicked, this, &MainWindow::onPrevClicked);
    connect(m_playPauseBtn, &QPushButton::clicked, this, &MainWindow::onPlayPauseClicked);
    connect(m_nextBtn, &QPushButton::clicked, this, &MainWindow::onNextClicked);
    connect(m_forwardBtn, &QPushButton::clicked, this, &MainWindow::onForwardClicked);

    m_volumeBtn = new QPushButton(m_bottomBar);
    m_volumeBtn->setIcon(QIcon(":/icons/volume_mid.svg"));
    connect(m_volumeBtn, &QPushButton::clicked, this, &MainWindow::onMuteClicked);

    m_volumeSlider = new ClickableSlider(Qt::Horizontal, m_bottomBar);
    m_volumeSlider->setRange(0, 200);
    m_volumeSlider->setValue(100);
    m_volumeSlider->setFixedWidth(70);
    m_volumeSlider->setStyleSheet(
        "QSlider::horizontal { height: 16px; background: transparent; }"
        "QSlider::groove:horizontal { height: 4px; background: rgba(255, 255, 255, 55); border-radius: 2px; }"
        "QSlider::handle:horizontal { width: 10px; height: 10px; background: white; margin-top: -3px; margin-bottom: -3px; border-radius: 5px; border: none; }"
        "QSlider::sub-page:horizontal { background: white; border-radius: 2px; }"
    );
    connect(m_volumeSlider, &QSlider::valueChanged, this, &MainWindow::onVolumeChanged);

    m_speedBtn = new QPushButton("1x", m_bottomBar);
    m_speedBtn->setStyleSheet("font-weight: 700; font-size: 12px; font-family: 'Consolas', 'Segoe UI', sans-serif;");
    connect(m_speedBtn, &QPushButton::clicked, this, &MainWindow::onSpeedClicked);
    
    m_aspectBtn = new QPushButton(m_bottomBar);
    m_aspectBtn->setIcon(QIcon(":/icons/aspect.svg"));
    connect(m_aspectBtn, &QPushButton::clicked, this, &MainWindow::onAspectClicked);
    m_fullscreenBtn = new QPushButton(m_bottomBar);
    m_fullscreenBtn->setIcon(QIcon(":/icons/fullscreen.svg"));
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
        "QWidget#brightnessBar { "
        "  background-color: rgba(30, 30, 30, 180); "
        "  border-radius: 10px; "
        "}"
        "QSlider::vertical { width: 16px; background: transparent; }"
        "QSlider::groove:vertical { width: 4px; background: rgba(255, 255, 255, 50); border-radius: 2px; }"
        "QSlider::handle:vertical { width: 12px; height: 12px; background: white; margin-left: -4px; margin-right: -4px; border-radius: 6px; border: none; }"
        "QSlider::add-page:vertical { background: white; border-radius: 2px; }"
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
        "QWidget#volumeBar { "
        "  background-color: rgba(30, 30, 30, 180); "
        "  border-radius: 10px; "
        "}"
        "QSlider::vertical { width: 16px; background: transparent; }"
        "QSlider::groove:vertical { width: 4px; background: rgba(255, 255, 255, 50); border-radius: 2px; }"
        "QSlider::handle:vertical { width: 12px; height: 12px; background: white; margin-left: -4px; margin-right: -4px; border-radius: 6px; border: none; }"
        "QSlider::add-page:vertical { background: white; border-radius: 2px; }"
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
    m_currentFile = file;
    m_thumbnailCache.clear();
    m_isGeneratingThumbnail = false;
    m_pendingThumbnailTime = -1;
    if (!m_thumbnailMpv) {
        m_thumbnailMpv = new ThumbnailMpv();
    }

    std::thread([this, file]() {
        m_thumbnailMpv->loadSource(file);
    }).detach();

    m_mpvWidget->loadFile(file);
    m_isPlaying = true;
    m_playPauseBtn->setIcon(QIcon(":/icons/pause.svg"));
}

void MainWindow::onOpenClicked()
{
    QString file = QFileDialog::getOpenFileName(this, "Open Video");
    if (!file.isEmpty()) {
        openFile(file);
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
        double pos = (position / 1000.0) * m_duration;
        m_currentTimeLabel->setText(formatTime(pos));
        m_remainingTimeLabel->setText("-" + formatTime(m_duration - pos));

        qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - m_lastSeekTime > 25) {
            m_lastSeekTime = now;
            m_mpvWidget->command(QVariantList() << "seek" << QString::number(pos) << "absolute+keyframes");
        }
    }
}

void MainWindow::onSliderReleased()
{
    m_isSeeking = false;
    if (m_duration > 0) {
        double pos = (m_seekSlider->value() / 1000.0) * m_duration;
        m_mpvWidget->command(QVariantList() << "seek" << QString::number(pos) << "absolute+exact");
        m_currentTimeLabel->setText(formatTime(pos));
        m_remainingTimeLabel->setText("-" + formatTime(m_duration - pos));
    }
    hideTimelinePreview();
}

void MainWindow::onVolumeChanged(int volume)
{
    if (m_syncingFromSystem) return;

    const int osVolume = qBound(0, volume, 100);

    m_syncingFromSystem = true;
    {
        QSignalBlocker blocker1(m_volumeSlider);
        m_volumeSlider->setValue(osVolume);
    }
    {
        QSignalBlocker blocker2(m_volumeHoverSlider);
        m_volumeHoverSlider->setValue(osVolume);
    }
    m_syncingFromSystem = false;

    // Set OS system volume and mute state
    WinOSIntegration::instance().setSystemVolume(osVolume / 100.0f);
    WinOSIntegration::instance().setMuted(osVolume == 0);

    // Set mpv volume to match
    m_mpvWidget->setVolume(osVolume);
    updateVolumeIcon(osVolume, osVolume == 0);
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
    if (!tempDir.isValid()) return {};
    const QString outPath = tempDir.path() + "/" + name;
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

    const QString normalizedPreset = aliases.value(preset, preset);
    QString resolvedPreset = normalizedPreset;
#if defined(_M_ARM64) || defined(__aarch64__)
    if (normalizedPreset == "Auto (Recommended)") {
        resolvedPreset = "Mode A (Fast)";
    }
#else
    if (normalizedPreset == "Auto (Recommended)") {
        resolvedPreset = "Mode A (HQ)";
    }
#endif

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

    // Apply beautiful pink glow to the shader button when one is active
    QGraphicsDropShadowEffect *glow = new QGraphicsDropShadowEffect(this);
    glow->setBlurRadius(15);
    glow->setColor(QColor(255, 105, 180, 200)); // vibrant pink glow (#FF69B4)
    glow->setOffset(0, 0);
    m_shaderBtn->setGraphicsEffect(glow);
    m_shaderBtn->setStyleSheet(
        "QPushButton { "
        "  background: rgba(255, 105, 180, 40); "
        "  border: 1px solid rgba(255, 105, 180, 180); "
        "  border-radius: 4px; "
        "}"
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
    if (m_isSeeking) return;
    if (!m_seekSlider->isSliderDown() && m_duration > 0) {
        m_seekSlider->setValue((position / m_duration) * 1000);
    }
    m_currentTimeLabel->setText(formatTime(position));
    m_remainingTimeLabel->setText("-" + formatTime(m_duration - position));
}

void MainWindow::updateDuration(double duration)
{
    m_duration = duration;
}

void MainWindow::resizeEvent(QResizeEvent *event)
{
    QMainWindow::resizeEvent(event);
    updateHudPositions();
}

void MainWindow::onRewindClicked() { m_mpvWidget->seek(-5.0); }
void MainWindow::onForwardClicked() { m_mpvWidget->seek(5.0); }
void MainWindow::onPrevClicked() { m_mpvWidget->command(QVariantList() << "playlist-prev"); }
void MainWindow::onNextClicked() { m_mpvWidget->command(QVariantList() << "playlist-next"); }
void MainWindow::onSpeedClicked()
{
    QMenu menu(this);
    menu.setWindowFlags(menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint);
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
    menu.setWindowFlags(menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint);
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
    menu.setWindowFlags(menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint);
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
    menu.setWindowFlags(menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint);
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
    menu.setWindowFlags(menu.windowFlags() | Qt::FramelessWindowHint | Qt::NoDropShadowWindowHint);
    menu.setAttribute(Qt::WA_TranslucentBackground);
    menu.setStyleSheet(
        "QMenu { "
        "  background-color: rgba(30, 30, 30, 230); "
        "  color: white; "
        "  border: 1px solid rgba(255, 255, 255, 40); "
        "  border-radius: 8px; "
        "  padding: 4px 0px; "
        "}"
        "QMenu::item { "
        "  padding: 6px 20px 6px 25px; "
        "  margin: 2px 6px; "
        "  border-radius: 4px; "
        "  font-size: 13px; "
        "}"
        "QMenu::item:selected { "
        "  background-color: rgba(255, 105, 180, 50); "
        "  border: 1px solid rgba(255, 105, 180, 100); "
        "}"
        "QMenu::item:checked { "
        "  color: #ff69b4; "
        "  font-weight: bold; "
        "}"
        "QMenu::separator { "
        "  height: 1px; "
        "  background: rgba(255, 255, 255, 25); "
        "  margin: 4px 0px; "
        "}"
    );

    QString currentPreset = m_settings.value("defaultShaderPreset", "Off").toString();
#if defined(_M_ARM64) || defined(__aarch64__)
    QString recommendedPreset = "Mode A (Fast)";
#else
    QString recommendedPreset = "Mode A (HQ)";
#endif

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
                static qint64 lastClickTime = 0;
                if (now - lastClickTime < QGuiApplication::styleHints()->mouseDoubleClickInterval()) {
                    m_clickTimer->stop();
                    toggleFullscreen();
                    lastClickTime = 0;
                } else {
                    lastClickTime = now;
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
    const bool muted = WinOSIntegration::instance().isMuted() || volumeValue == 0;

    const float sysBrightness = WinOSIntegration::instance().getSystemBrightness();
    const int brightnessValue = qRound(sysBrightness * 100.0f);

    m_syncingFromSystem = true;
    {
        QSignalBlocker mainBlocker(m_volumeSlider);
        if (m_volumeSlider->value() != volumeValue) {
            m_volumeSlider->setValue(volumeValue);
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
    if (m_mpvWidget->getProperty("volume").toInt() != volumeValue)
        m_mpvWidget->setVolume(volumeValue);

    if (!m_volumeSlider->isSliderDown()) {
        m_isMuted = muted;
        updateVolumeIcon(volumeValue, muted);
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
}

void MainWindow::keyPressEvent(QKeyEvent *event)
{
    switch (event->key()) {
    case Qt::Key_Space:
        onPlayPauseClicked();
        break;
    case Qt::Key_F:
        toggleFullscreen();
        break;
    case Qt::Key_Escape:
        if (isFullScreen()) showNormal();
        break;
    case Qt::Key_Left:
        m_mpvWidget->seek(-5.0);
        break;
    case Qt::Key_Right:
        m_mpvWidget->seek(5.0);
        break;
    case Qt::Key_Up:
        m_volumeSlider->setValue(m_volumeSlider->value() + 5);
        break;
    case Qt::Key_Down:
        m_volumeSlider->setValue(m_volumeSlider->value() - 5);
        break;
    case Qt::Key_M:
        onMuteClicked();
        break;
    default:
        QMainWindow::keyPressEvent(event);
    }
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
        {"AudioDelayDecrease", "Audio Delay Decrease (1ms)", "Ctrl+["}
    };
}

void MainWindow::handleShortcutTrigger(const QString &action)
{
    if (action == "PlayPause") {
        onPlayPauseClicked();
    } else if (action == "Fullscreen") {
        toggleFullscreen();
    } else if (action == "SeekBackward") {
        m_mpvWidget->seek(-5.0);
    } else if (action == "SeekForward") {
        m_mpvWidget->seek(5.0);
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

    double ratio = static_cast<double>(pos.x()) / m_seekSlider->width();
    ratio = std::clamp(ratio, 0.0, 1.0);
    double time = ratio * m_duration;
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

    std::thread([this, time, cacheKey]() {
        m_thumbnailMpv->loadSource(m_currentFile);
        QImage img = m_thumbnailMpv->generateThumbnail(time);

        QMetaObject::invokeMethod(this, [this, img, cacheKey]() {
            if (!img.isNull()) {
                if (m_thumbnailCache.size() > 500) {
                    m_thumbnailCache.clear();
                }
                m_thumbnailCache.insert(cacheKey, img);
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
        }, Qt::QueuedConnection);
    }).detach();
}

