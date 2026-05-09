#include "MainWindow.h"
#include "WinOSIntegration.h"
#include <QFileDialog>
#include <QKeyEvent>
#include <QTime>
#include <QFile>
#include <QTemporaryDir>
#include <QDebug>
#include <QTimer>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent), m_settings("GlassPlayer", "Settings")
{
    setupUi();

    connect(m_mpvWidget, &MpvWidget::positionChanged, this, &MainWindow::updatePosition);
    connect(m_mpvWidget, &MpvWidget::durationChanged, this, &MainWindow::updateDuration);
    
    // Sync initial volume
    float sysVol = WinOSIntegration::instance().getSystemVolume();
    m_volumeSlider->setValue(sysVol * 100);
    m_isMuted = WinOSIntegration::instance().isMuted();
    
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

    setMouseTracking(true);
    centralWidget()->setMouseTracking(true);
    m_mpvWidget->setMouseTracking(true);
    m_rcloneBrowser = new RcloneBrowser(this);
    connect(m_rcloneBrowser, &RcloneBrowser::fileSelected, this, &MainWindow::openFile);

    // Apply saved settings
    QStringList keys = m_settings.allKeys();
    for (const QString &key : keys) {
        applySettingToMpv(key, m_settings.value(key));
    }

    // Show welcome only if no file was provided AND setting is enabled
    if (!m_welcomeSuppressed && m_settings.value("showWelcome", true).toBool()) {
        QTimer::singleShot(0, this, [this]() {
            m_welcomeWindow->exec();
        });
    }
}

MainWindow::~MainWindow()
{
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

    QWidget *centralWidget = new QWidget(this);
    setCentralWidget(centralWidget);

    // Main layout is just the MPV widget filling everything
    QVBoxLayout *mainLayout = new QVBoxLayout(centralWidget);
    mainLayout->setContentsMargins(0, 0, 0, 0);
    mainLayout->setSpacing(0);

    m_mpvWidget = new MpvWidget(centralWidget);
    mainLayout->addWidget(m_mpvWidget);

    setupTopBar();
    setupBottomBar();
    setupBrightnessBar();

    updateHudPositions();
}

void MainWindow::setupTopBar()
{
    m_topBar = new QWidget(this);
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

    layout->addStretch();

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

    m_topBar->show();
}

void MainWindow::setupBottomBar()
{
    m_bottomBar = new QWidget(this);
    m_bottomBar->setObjectName("bottomBar");
    m_bottomBar->setFixedHeight(100);
    m_bottomBar->setFixedWidth(1248); // Will be updated in resizeEvent
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
        "QSlider::groove:horizontal { height: 4px; background: rgba(255, 255, 255, 50); border-radius: 2px; }"
        "QSlider::handle:horizontal { width: 12px; height: 12px; background: white; margin: -4px 0; border-radius: 6px; }"
        "QSlider::sub-page:horizontal { background: white; border-radius: 2px; }"
    );

    QVBoxLayout *mainLayout = new QVBoxLayout(m_bottomBar);
    mainLayout->setContentsMargins(15, 10, 15, 10);
    mainLayout->setSpacing(5);

    // Timeline Row
    QHBoxLayout *timeRow = new QHBoxLayout();
    m_currentTimeLabel = new QLabel("0:00", m_bottomBar);
    m_currentTimeLabel->setFixedWidth(50);
    
    m_seekSlider = new QSlider(Qt::Horizontal, m_bottomBar);
    m_seekSlider->setRange(0, 1000);
    connect(m_seekSlider, &QSlider::sliderMoved, this, &MainWindow::onSliderMoved);

    m_remainingTimeLabel = new QLabel("-0:00", m_bottomBar);
    m_remainingTimeLabel->setFixedWidth(50);
    m_remainingTimeLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);

    timeRow->addWidget(m_currentTimeLabel);
    timeRow->addWidget(m_seekSlider);
    timeRow->addWidget(m_remainingTimeLabel);
    mainLayout->addLayout(timeRow);

    // Controls Row
    QHBoxLayout *controlsRow = new QHBoxLayout();
    
    // Left Group
    m_subtitleBtn = new QPushButton(m_bottomBar);
    m_subtitleBtn->setIcon(QIcon(":/icons/subtitle.svg"));
    m_audioBtn = new QPushButton(m_bottomBar);
    m_audioBtn->setIcon(QIcon(":/icons/audio.svg"));
    m_shaderBtn = new QPushButton(m_bottomBar);
    m_shaderBtn->setIcon(QIcon(":/icons/shader.svg"));
    connect(m_shaderBtn, &QPushButton::clicked, this, &MainWindow::onSettingsClicked); // Temp

    controlsRow->addWidget(m_subtitleBtn);
    controlsRow->addWidget(m_audioBtn);
    controlsRow->addWidget(m_shaderBtn);
    controlsRow->addStretch();

    // Center Group
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

    controlsRow->addWidget(m_rewindBtn);
    controlsRow->addWidget(m_prevBtn);
    controlsRow->addWidget(m_playPauseBtn);
    controlsRow->addWidget(m_nextBtn);
    controlsRow->addWidget(m_forwardBtn);
    controlsRow->addStretch();

    // Right Group
    m_volumeBtn = new QPushButton(m_bottomBar);
    m_volumeBtn->setIcon(QIcon(":/icons/volume_mid.svg"));
    m_volumeSlider = new QSlider(Qt::Horizontal, m_bottomBar);
    m_volumeSlider->setRange(0, 150);
    m_volumeSlider->setValue(100);
    m_volumeSlider->setFixedWidth(80);
    connect(m_volumeSlider, &QSlider::valueChanged, this, &MainWindow::onVolumeChanged);

    m_speedBtn = new QPushButton("1x", m_bottomBar);
    m_speedBtn->setStyleSheet("font-weight: bold; font-size: 13px;");
    
    m_aspectBtn = new QPushButton(m_bottomBar);
    // TODO: Add aspect icon if needed
    m_fullscreenBtn = new QPushButton(m_bottomBar);
    m_fullscreenBtn->setIcon(QIcon(":/icons/fullscreen.svg"));
    connect(m_fullscreenBtn, &QPushButton::clicked, this, &MainWindow::toggleFullscreen);

    controlsRow->addWidget(m_volumeBtn);
    controlsRow->addWidget(m_volumeSlider);
    controlsRow->addWidget(m_speedBtn);
    controlsRow->addWidget(m_aspectBtn);
    controlsRow->addWidget(m_fullscreenBtn);

    // Set icon sizes for all buttons in controls row
    QList<QPushButton*> btns = m_bottomBar->findChildren<QPushButton*>();
    for (QPushButton* btn : btns) {
        if (btn != m_playPauseBtn && btn != m_speedBtn) {
            btn->setIconSize(QSize(20, 20));
        }
    }

    mainLayout->addLayout(controlsRow);
    m_bottomBar->show();
}

void MainWindow::setupBrightnessBar()
{
    m_brightnessBar = new QWidget(this);
    m_brightnessBar->setObjectName("brightnessBar");
    m_brightnessBar->setFixedWidth(40);
    m_brightnessBar->setFixedHeight(200);
    m_brightnessBar->setStyleSheet(
        "QWidget#brightnessBar { "
        "  background-color: rgba(30, 30, 30, 180); "
        "  border-radius: 10px; "
        "}"
        "QSlider::groove:vertical { width: 4px; background: rgba(255, 255, 255, 50); border-radius: 2px; }"
        "QSlider::handle:vertical { width: 12px; height: 12px; background: white; margin: 0 -4px; border-radius: 6px; }"
        "QSlider::add-page:vertical { background: white; border-radius: 2px; }"
    );

    QVBoxLayout *layout = new QVBoxLayout(m_brightnessBar);
    layout->setContentsMargins(0, 15, 0, 15);
    layout->setAlignment(Qt::AlignCenter);

    QLabel *icon = new QLabel(m_brightnessBar);
    icon->setPixmap(QIcon(":/icons/sun.svg").pixmap(16, 16));
    layout->addWidget(icon);

    m_brightnessSlider = new QSlider(Qt::Vertical, m_brightnessBar);
    m_brightnessSlider->setRange(0, 100);
    float sysBright = WinOSIntegration::instance().getSystemBrightness();
    m_brightnessSlider->setValue(sysBright * 100);
    connect(m_brightnessSlider, &QSlider::valueChanged, this, &MainWindow::onBrightnessChanged);
    layout->addWidget(m_brightnessSlider);

    m_brightnessBar->show();
}

void MainWindow::updateHudPositions()
{
    if (m_topBar) {
        m_topBar->setGeometry(0, 0, width(), 44);
        m_topBar->raise();
    }
    if (m_bottomBar) {
        int w = width() - 32;
        int x = 16;
        int y = height() - 100 - 16;
        m_bottomBar->setGeometry(x, y, w, 100);
        m_bottomBar->raise();
    }
    if (m_brightnessBar) {
        int x = 16;
        int y = (height() - 200) / 2;
        m_brightnessBar->setGeometry(x, y, 40, 200);
        m_brightnessBar->raise();
    }
}


void MainWindow::openFile(const QString &file)
{
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

void MainWindow::onPlayPauseClicked()
{
    if (m_isPlaying) {
        m_mpvWidget->pause();
        m_isPlaying = false;
        m_playPauseBtn->setIcon(QIcon(":/icons/play.svg"));
    } else {
        m_mpvWidget->play();
        m_isPlaying = true;
        m_playPauseBtn->setIcon(QIcon(":/icons/pause.svg"));
    }
}

void MainWindow::onSliderMoved(int position)
{
    if (m_duration > 0) {
        double pos = (position / 1000.0) * m_duration;
        m_mpvWidget->setProperty("time-pos", pos);
    }
}

void MainWindow::onVolumeChanged(int volume)
{
    float level = volume / 100.0f;
    WinOSIntegration::instance().setSystemVolume(level);
    m_mpvWidget->setVolume(volume); // Also keep mpv volume in sync for internal processing
    
    if (volume == 0) m_volumeBtn->setIcon(QIcon(":/icons/volume_mute.svg"));
    else if (volume < 80) m_volumeBtn->setIcon(QIcon(":/icons/volume_mid.svg"));
    else m_volumeBtn->setIcon(QIcon(":/icons/volume_high.svg"));
}

void MainWindow::onMuteClicked()
{
    m_isMuted = !m_isMuted;
    WinOSIntegration::instance().setMuted(m_isMuted);
    m_mpvWidget->setProperty("mute", m_isMuted ? "yes" : "no");
    m_volumeBtn->setIcon(QIcon(m_isMuted ? ":/icons/volume_mute.svg" : ":/icons/volume_mid.svg"));
}

// Function to copy a shader from qrc to temp and return its path
static QString extractShader(const QString& name) {
    static QTemporaryDir tempDir;
    if (!tempDir.isValid()) return "";

    QString qrcPath = ":/shaders/" + name;
    QString outPath = tempDir.path() + "/" + name;

    if (!QFile::exists(outPath)) {
        QFile file(qrcPath);
        if (file.open(QIODevice::ReadOnly)) {
            QFile outFile(outPath);
            if (outFile.open(QIODevice::WriteOnly)) {
                outFile.write(file.readAll());
            }
        }
    }
    return outPath;
}

void MainWindow::onShaderPresetChanged(int index)
{
    // Unused, keeping signature if needed or we can remove it. But wait, we should just delete the whole method.
}

void MainWindow::applySettingToMpv(const QString &key, const QVariant &value)
{
    if (key == "hwdec") {
        m_mpvWidget->setProperty("hwdec", value.toString());
    } else if (key == "debandEnabled") {
        m_mpvWidget->setProperty("deband", value.toBool() ? "yes" : "no");
    } else if (key == "audioOutput") {
        m_mpvWidget->setProperty("ao", value.toString());
    } else if (key == "audioChannels") {
        m_mpvWidget->setProperty("audio-channels", value.toString());
    } else if (key == "cacheEnabled") {
        m_mpvWidget->setProperty("cache", value.toBool() ? "yes" : "no");
    } else if (key == "cacheSecs") {
        m_mpvWidget->setProperty("cache-secs", value.toString());
    } else if (key == "defaultShaderPreset") {
        QString val = value.toString();
        applyShaderPreset(val);
    }
}

void MainWindow::setAnime4kPreset(const QString& preset)
{
    applyShaderPreset(preset);
}

void MainWindow::applyShaderPreset(const QString& preset)
{
    if (preset.isEmpty()) {
        m_mpvWidget->setProperty("glsl-shaders", "");
        return;
    }

    QStringList shaders;

    // Exact mapping of Anime4K presets to their constituent shaders
    if (preset == "ModeA") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Restore_CNN_VL.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeB") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Restore_CNN_Soft_VL.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeC") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Upscale_Denoise_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeAA") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Restore_CNN_VL.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_VL.glsl")
                << extractShader("Anime4K_Restore_CNN_M.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeBB") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Restore_CNN_Soft_VL.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Restore_CNN_Soft_M.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeCA") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Upscale_Denoise_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Restore_CNN_M.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeAFast") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Restore_CNN_M.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_S.glsl");
    } else if (preset == "ModeBFast") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Restore_CNN_Soft_M.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_S.glsl");
    } else if (preset == "ModeCFast") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Upscale_Denoise_CNN_x2_M.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_S.glsl");
    } else if (preset == "ModeAAFast") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Restore_CNN_M.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl")
                << extractShader("Anime4K_Restore_CNN_S.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_S.glsl");
    } else if (preset == "ModeBBFast") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Restore_CNN_Soft_M.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Restore_CNN_Soft_S.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_S.glsl");
    } else if (preset == "ModeCAFast") {
        shaders << extractShader("Anime4K_Clamp_Highlights.glsl")
                << extractShader("Anime4K_Upscale_Denoise_CNN_x2_M.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Restore_CNN_S.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_S.glsl");
    }

    // Join shaders with path separator and set to mpv
    // mpv expects a colon-separated list on linux/mac, but semicolon-separated on Windows
#ifdef Q_OS_WIN
    QString shaderStr = shaders.join(";");
#else
    QString shaderStr = shaders.join(":");
#endif

    m_mpvWidget->setProperty("glsl-shaders", shaderStr);
}

QString MainWindow::formatTime(double seconds)
{
    int h = seconds / 3600;
    int m = (static_cast<int>(seconds) % 3600) / 60;
    int s = static_cast<int>(seconds) % 60;
    if (h > 0)
        return QString::asprintf("%02d:%02d:%02d", h, m, s);
    return QString::asprintf("%02d:%02d", m, s);
}

void MainWindow::updatePosition(double position)
{
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
void MainWindow::onPrevClicked() { m_mpvWidget->setProperty("playlist-prev", ""); }
void MainWindow::onNextClicked() { m_mpvWidget->setProperty("playlist-next", ""); }
void MainWindow::onSpeedClicked() { /* Implement speed cycle */ }
void MainWindow::onAspectClicked() { /* Implement aspect cycle */ }
void MainWindow::onSubtitleClicked() { /* Implement sub cycle */ }
void MainWindow::onAudioClicked() { /* Implement audio cycle */ }
void MainWindow::onUrlClicked() { /* Show URL input */ }
void MainWindow::onFullscreenClicked() { toggleFullscreen(); }

void MainWindow::onBrightnessChanged(int level)
{
    WinOSIntegration::instance().setSystemBrightness(level / 100.0f);
}

void MainWindow::mouseMoveEvent(QMouseEvent *event)
{
    showHud();
    QMainWindow::mouseMoveEvent(event);
}

void MainWindow::showHud()
{
    m_topBar->show();
    m_bottomBar->show();
    m_brightnessBar->show();
    m_hudTimer->start(3000);
}

void MainWindow::hideHud()
{
    // underMouse() is unreliable for floating overlay widgets — check cursor position manually
    auto cursorPos = QCursor::pos();
    bool overBottom  = m_bottomBar->geometry().contains(mapFromGlobal(cursorPos));
    bool overTop     = m_topBar->geometry().contains(mapFromGlobal(cursorPos));
    bool overBright  = m_brightnessBar->geometry().contains(mapFromGlobal(cursorPos));

    if (!overBottom && !overTop && !overBright && m_isPlaying) {
        m_topBar->hide();
        m_bottomBar->hide();
        m_brightnessBar->hide();
    } else {
        m_hudTimer->start(3000);
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
