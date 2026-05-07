#include "MainWindow.h"
#include <QFileDialog>
#include <QKeyEvent>
#include <QTime>
#include <QFile>
#include <QTemporaryDir>
#include <QDebug>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
{
    setupUi();

    connect(m_mpvWidget, &MpvWidget::positionChanged, this, &MainWindow::updatePosition);
    connect(m_mpvWidget, &MpvWidget::durationChanged, this, &MainWindow::updateDuration);
    connect(m_mpvWidget, &MpvWidget::eofReached, this, [this](){
        m_isPlaying = false;
        m_playPauseBtn->setText("Play");
    });
}

MainWindow::~MainWindow()
{
}

void MainWindow::setupUi()
{
    setWindowTitle("Glass Player");
    resize(1280, 720);

    QWidget *centralWidget = new QWidget(this);
    setCentralWidget(centralWidget);

    QVBoxLayout *mainLayout = new QVBoxLayout(centralWidget);
    mainLayout->setContentsMargins(0, 0, 0, 0);
    mainLayout->setSpacing(0);

    m_mpvWidget = new MpvWidget(this);
    mainLayout->addWidget(m_mpvWidget, 1); // taking most space

    // Controls Layout
    QWidget *controlsWidget = new QWidget(this);
    QHBoxLayout *controlsLayout = new QHBoxLayout(controlsWidget);
    controlsLayout->setContentsMargins(10, 10, 10, 10);

    QPushButton *openBtn = new QPushButton("Open", this);
    connect(openBtn, &QPushButton::clicked, this, &MainWindow::onOpenClicked);

    m_playPauseBtn = new QPushButton("Pause", this);
    connect(m_playPauseBtn, &QPushButton::clicked, this, &MainWindow::onPlayPauseClicked);

    m_timeLabel = new QLabel("00:00 / 00:00", this);

    m_seekSlider = new QSlider(Qt::Horizontal, this);
    m_seekSlider->setRange(0, 1000);
    connect(m_seekSlider, &QSlider::sliderMoved, this, &MainWindow::onSliderMoved);

    m_muteBtn = new QPushButton("Mute", this);
    connect(m_muteBtn, &QPushButton::clicked, this, &MainWindow::onMuteClicked);

    m_volumeSlider = new QSlider(Qt::Horizontal, this);
    m_volumeSlider->setRange(0, 130);
    m_volumeSlider->setValue(100);
    m_volumeSlider->setFixedWidth(100);
    connect(m_volumeSlider, &QSlider::valueChanged, this, &MainWindow::onVolumeChanged);

    // Shader selection
    m_shaderCombo = new QComboBox(this);
    m_shaderCombo->addItem("No Shaders", "");
    m_shaderCombo->addItem("Anime4K: Mode A (HQ)", "ModeA");
    m_shaderCombo->addItem("Anime4K: Mode B (HQ)", "ModeB");
    m_shaderCombo->addItem("Anime4K: Mode C (HQ)", "ModeC");
    m_shaderCombo->addItem("Anime4K: Mode A+A (HQ)", "ModeAA");
    m_shaderCombo->addItem("Anime4K: Mode B+B (HQ)", "ModeBB");
    m_shaderCombo->addItem("Anime4K: Mode C+A (HQ)", "ModeCA");
    connect(m_shaderCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), this, &MainWindow::onShaderPresetChanged);

    controlsLayout->addWidget(openBtn);
    controlsLayout->addWidget(m_playPauseBtn);
    controlsLayout->addWidget(m_timeLabel);
    controlsLayout->addWidget(m_seekSlider, 1);
    controlsLayout->addWidget(m_muteBtn);
    controlsLayout->addWidget(m_volumeSlider);
    controlsLayout->addWidget(new QLabel("Anime4K:", this));
    controlsLayout->addWidget(m_shaderCombo);

    mainLayout->addWidget(controlsWidget);
}

void MainWindow::openFile(const QString &file)
{
    m_mpvWidget->loadFile(file);
    m_isPlaying = true;
    m_playPauseBtn->setText("Pause");
}

void MainWindow::onOpenClicked()
{
    QString file = QFileDialog::getOpenFileName(this, "Open Video");
    if (!file.isEmpty()) {
        openFile(file);
    }
}

void MainWindow::onPlayPauseClicked()
{
    if (m_isPlaying) {
        m_mpvWidget->pause();
        m_isPlaying = false;
        m_playPauseBtn->setText("Play");
    } else {
        m_mpvWidget->play();
        m_isPlaying = true;
        m_playPauseBtn->setText("Pause");
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
    m_mpvWidget->setVolume(volume);
}

void MainWindow::onMuteClicked()
{
    m_mpvWidget->toggleMute();
    QString mute = m_mpvWidget->getProperty("mute").toString();
    m_muteBtn->setText(mute == "yes" ? "Unmute" : "Mute");
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
    QString presetId = m_shaderCombo->itemData(index).toString();
    applyShaderPreset(presetId);
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
        shaders << extractShader("Anime4K_Restore_CNN_VL.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeB") {
        shaders << extractShader("Anime4K_Restore_CNN_Soft_VL.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeC") {
        shaders << extractShader("Anime4K_Upscale_Denoise_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeAA") {
        shaders << extractShader("Anime4K_Restore_CNN_VL.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_VL.glsl")
                << extractShader("Anime4K_Restore_CNN_M.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeBB") {
        shaders << extractShader("Anime4K_Restore_CNN_Soft_VL.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Restore_CNN_Soft_M.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
    } else if (preset == "ModeCA") {
        shaders << extractShader("Anime4K_Upscale_Denoise_CNN_x2_VL.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x2.glsl")
                << extractShader("Anime4K_AutoDownscalePre_x4.glsl")
                << extractShader("Anime4K_Restore_CNN_M.glsl")
                << extractShader("Anime4K_Upscale_CNN_x2_M.glsl");
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
    m_timeLabel->setText(formatTime(position) + " / " + formatTime(m_duration));
}

void MainWindow::updateDuration(double duration)
{
    m_duration = duration;
}

void MainWindow::toggleFullscreen()
{
    if (isFullScreen()) {
        showNormal();
    } else {
        showFullScreen();
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
