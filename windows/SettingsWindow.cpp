#include "SettingsWindow.h"
#include <QScrollArea>
#include <QPushButton>
#include <QKeyEvent>
#include <QKeySequence>
#include <QGridLayout>

SettingsWindow::SettingsWindow(QWidget *parent)
    : QDialog(parent), m_settings("GlassPlayer", "Settings")
{
    setWindowFlags(windowFlags() | Qt::WindowStaysOnTopHint);
    setupUi();
}

SettingsWindow::~SettingsWindow()
{
}

void SettingsWindow::setupUi()
{
    setWindowTitle("Settings");
    setMinimumSize(720, 560);

    QHBoxLayout *mainLayout = new QHBoxLayout(this);
    mainLayout->setContentsMargins(0, 0, 0, 0);
    mainLayout->setSpacing(0);

    m_sidebar = new QListWidget(this);
    m_sidebar->setFixedWidth(180);
    m_sidebar->setStyleSheet(
        "QListWidget { background: #f0f0f0; border: none; outline: none; padding-top: 10px; }"
        "QListWidget::item { height: 36px; padding-left: 15px; border-left: 3px solid transparent; color: #333; }"
        "QListWidget::item:selected { background: #e0e0e0; border-left: 3px solid #0078d4; color: #000; }"
    );
    connect(m_sidebar, &QListWidget::currentRowChanged, this, &SettingsWindow::onSidebarItemChanged);
    mainLayout->addWidget(m_sidebar);

    m_contentStack = new QStackedWidget(this);
    mainLayout->addWidget(m_contentStack, 1);

    buildGeneralSection();
    buildVideoSection();
    buildAudioSection();
    buildSubtitlesSection();
    buildNetworkSection();
    buildScalingSection();
    buildColorSection();
    buildAnime4KSection();
    buildShortcutsSection();

    if (m_sidebar->count() > 0) {
        m_sidebar->setCurrentRow(0);
    }
}

void SettingsWindow::onSidebarItemChanged(int currentRow)
{
    m_contentStack->setCurrentIndex(currentRow);
}

void SettingsWindow::emitSettingChange(const QString &key, const QVariant &value)
{
    m_settings.setValue(key, value);
    emit settingChanged(key, value);
}

QWidget* SettingsWindow::createSectionWidget()
{
    QScrollArea *scroll = new QScrollArea(this);
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);

    QWidget *container = new QWidget(scroll);
    QVBoxLayout *layout = new QVBoxLayout(container);
    layout->setAlignment(Qt::AlignTop);
    layout->setSpacing(12);
    layout->setContentsMargins(20, 20, 20, 20);
    
    scroll->setWidget(container);
    m_contentStack->addWidget(scroll);
    
    return container;
}

QCheckBox* SettingsWindow::addToggle(QWidget *parent, QVBoxLayout *layout, const QString &title, const QString &key, bool defaultValue)
{
    QCheckBox *cb = new QCheckBox(title, parent);
    bool val = m_settings.value(key, defaultValue).toBool();
    cb->setChecked(val);
    connect(cb, &QCheckBox::toggled, this, [this, key](bool checked){
        emitSettingChange(key, checked);
    });
    layout->addWidget(cb);
    return cb;
}

QComboBox* SettingsWindow::addCombo(QWidget *parent, QVBoxLayout *layout, const QString &title, const QString &key, const QStringList &options, const QString &defaultValue)
{
    QHBoxLayout *hLayout = new QHBoxLayout();
    QLabel *lbl = new QLabel(title, parent);
    QComboBox *cb = new QComboBox(parent);
    cb->addItems(options);
    
    QString val = m_settings.value(key, defaultValue).toString();
    int idx = cb->findText(val);
    if (idx >= 0) cb->setCurrentIndex(idx);

    connect(cb, &QComboBox::currentTextChanged, this, [this, key](const QString &text){
        emitSettingChange(key, text);
    });
    
    hLayout->addWidget(lbl);
    hLayout->addWidget(cb);
    hLayout->addStretch();
    layout->addLayout(hLayout);
    return cb;
}

void SettingsWindow::buildGeneralSection()
{
    m_sidebar->addItem("General");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>General</h2>", container);
    layout->addWidget(header);

    addToggle(container, layout, "Resume playback where you left off", "resumePlayback", true);
    addToggle(container, layout, "Pause when window loses focus", "pauseOnFocusLoss", false);
    addToggle(container, layout, "Show welcome window on launch", "showWelcome", true);
    addToggle(container, layout, "Quit when all windows are closed", "quitWhenAllClosed", false);
    addToggle(container, layout, "Keep window on top during playback", "keepOnTop", false);
    
    addCombo(container, layout, "Window Resize Behavior", "windowResize", 
             {"Never resize", "Fit to video", "Resize to 50%", "Resize to 75%", "Resize to 100%"}, "Never resize");
             
    addCombo(container, layout, "Cursor Auto-hide (ms)", "cursorAutohide", 
             {"500", "800", "1000", "2000", "3000", "never"}, "800");
}

void SettingsWindow::buildVideoSection()
{
    m_sidebar->addItem("Video");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>Video</h2>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Hardware Decoding", "hwdec", 
             {"d3d11va-copy", "dxva2-copy", "auto-safe", "auto", "no"}, "auto-safe");
             
    addCombo(container, layout, "Hardware Decode Codecs", "hwdecCodecs", 
             {"all", "h264,hevc,vp9,av1"}, "all");
             
    addCombo(container, layout, "Default Speed", "defaultSpeed", 
             {"0.25x", "0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x", "3x", "4x"}, "1x");
             
    addCombo(container, layout, "Screenshot Format", "screenshotFormat", 
             {"png", "jpg", "webp"}, "png");
             
    addCombo(container, layout, "Screenshot JPEG Quality", "screenshotJpegQuality", 
             {"50", "70", "85", "95", "100"}, "85");

    layout->addSpacing(10);
    QLabel *debandHeader = new QLabel("<h3>Debanding</h3>", container);
    layout->addWidget(debandHeader);

    addToggle(container, layout, "Enable debanding", "debandEnabled", false);
    
    addCombo(container, layout, "Deband Iterations", "debandIterations", 
             {"1", "2", "3", "4", "8"}, "4");
             
    addCombo(container, layout, "Deband Threshold", "debandThreshold", 
             {"20", "25", "30", "35", "40", "48", "64"}, "35");
             
    addCombo(container, layout, "Deband Range", "debandRange", 
             {"8", "12", "16", "20", "24", "32"}, "16");
             
    addCombo(container, layout, "Deband Grain", "debandGrain", 
             {"0", "2", "4", "6", "8", "12", "16", "24", "48"}, "4");
}

void SettingsWindow::buildAudioSection()
{
    m_sidebar->addItem("Audio");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>Audio</h2>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Maximum Volume", "volumeMax", 
             {"100%", "150%", "200%", "300%"}, "200%");
             
    addCombo(container, layout, "Audio Output", "audioOutput", 
             {"wasapi", "openal", "auto"}, "wasapi");
             
    addCombo(container, layout, "Audio Channels", "audioChannels", 
             {"auto", "auto-safe", "stereo", "5.1", "7.1"}, "auto");
             
    addToggle(container, layout, "Audio passthrough (AC3, EAC3, TrueHD, DTS-HD)", "audioPassthrough", true);
    
    addCombo(container, layout, "Preferred Audio Language", "audioLang", 
             {"eng,en,jpn,jp", "jpn,jp,eng,en", "eng,en", "jpn,jp", "kor,ko,eng,en", "chi,zh,eng,en"}, "eng,en,jpn,jp");
             
    addCombo(container, layout, "Default Audio Delay", "audioDelay", 
             {"-0.50", "-0.25", "-0.10", "0", "0.10", "0.25", "0.50"}, "0");
             
    addCombo(container, layout, "Default Volume", "defaultVolume", 
             {"25", "50", "75", "100", "125", "150"}, "100");
}

void SettingsWindow::buildSubtitlesSection()
{
    m_sidebar->addItem("Subtitles");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>Subtitles</h2>", container);
    layout->addWidget(header);

    addToggle(container, layout, "Auto-load external subtitles", "subAutoLoad", true);
    
    addCombo(container, layout, "Preferred Subtitle Language", "subLang", 
             {"eng,en,enUS", "jpn,jp", "kor,ko", "chi,zh", "spa,es", "fre,fr", "ger,de", "por,pt"}, "eng,en,enUS");
             
    addCombo(container, layout, "Font Size", "subFontSize", 
             {"20", "24", "28", "32", "36", "40", "48", "56", "64"}, "36");
             
    addCombo(container, layout, "Font", "subFont", 
             {"(Default)", "Segoe UI", "Arial", "Courier New", "Verdana", "Times New Roman"}, "(Default)");
             
    addCombo(container, layout, "Position", "subPosition", 
             {"Bottom", "Top"}, "Bottom");
             
    addCombo(container, layout, "Border Size", "subBorderSize", 
             {"0", "1", "2", "3", "4", "5"}, "3");
             
    addCombo(container, layout, "Shadow Offset", "subShadowOffset", 
             {"0", "1", "2", "3", "4"}, "0");
             
    addToggle(container, layout, "Override ASS styles", "subAssOverride", false);
}

void SettingsWindow::buildNetworkSection()
{
    m_sidebar->addItem("Network");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>Network & Streaming</h2>", container);
    layout->addWidget(header);

    addToggle(container, layout, "Enable cache", "cacheEnabled", true);
    
    addCombo(container, layout, "Demuxer Cache Size", "cacheSizeMB", 
             {"64 MB", "128 MB", "256 MB", "512 MB", "1024 MB", "2000 MB"}, "2000 MB");
             
    addCombo(container, layout, "Demuxer Back Buffer", "cacheBackMB", 
             {"64 MB", "128 MB", "256 MB", "500 MB", "1024 MB"}, "500 MB");
             
    addCombo(container, layout, "Read-ahead (seconds)", "readaheadSecs", 
             {"10", "30", "60", "120", "300"}, "60");
             
    addCombo(container, layout, "Cache Duration (seconds)", "cacheSecs", 
             {"30", "60", "120", "300", "600"}, "120");
             
    addCombo(container, layout, "Network Timeout (seconds)", "networkTimeout", 
             {"15", "30", "60", "120"}, "60");
             
    addToggle(container, layout, "Force seekable streams", "forceSeekable", true);
    addToggle(container, layout, "Auto reconnect on failure", "reconnect", true);
    
    addCombo(container, layout, "User Agent", "userAgent", 
             {"(Default)", "Mozilla/5.0 (Windows NT)", "VLC/3.0"}, "(Default)");
}

void SettingsWindow::buildScalingSection()
{
    m_sidebar->addItem("Scaling");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>Scaling & Rendering</h2>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Video Profile", "videoProfile", 
             {"default", "high-quality", "fast"}, "high-quality");

    addCombo(container, layout, "Upscale Filter", "scaleFilter", 
             {"ewa_lanczossharp", "ewa_lanczos", "lanczos", "spline36", "mitchell", "bilinear", "catmull_rom"}, "ewa_lanczossharp");
             
    addCombo(container, layout, "Downscale Filter", "dscaleFilter", 
             {"mitchell", "lanczos", "spline36", "bilinear", "catmull_rom", "ewa_lanczos"}, "mitchell");
             
    addCombo(container, layout, "Chroma Scaler", "cscaleFilter", 
             {"mitchell", "lanczos", "spline36", "bilinear", "catmull_rom", "ewa_lanczos", "ewa_lanczossharp"}, "mitchell");
             
    addCombo(container, layout, "Dither Depth", "ditherDepth", 
             {"auto", "no", "8", "10"}, "auto");
             
    addCombo(container, layout, "Dither Algorithm", "ditherAlgo", 
             {"fruit", "ordered", "error-diffusion", "no"}, "fruit");
             
    addToggle(container, layout, "Correct downscaling", "correctDownscaling", true);
    addToggle(container, layout, "Linear downscaling", "linearDownscaling", true);
    addToggle(container, layout, "Sigmoid upscaling", "sigmoidUpscaling", true);
}

void SettingsWindow::buildColorSection()
{
    m_sidebar->addItem("Color");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>Color & HDR</h2>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Tone Mapping", "toneMapping", 
             {"auto", "spline", "bt.2390", "reinhard", "hable", "mobius", "clip", "gamma", "linear"}, "spline");
             
    addCombo(container, layout, "Tone Mapping Mode", "toneMappingMode", 
             {"auto", "luma", "max", "rgb", "hybrid"}, "auto");
             
    addToggle(container, layout, "HDR compute peak (dynamic)", "hdrComputePeak", true);
    addToggle(container, layout, "Target colorspace hint (EDR/XDR)", "targetColorspaceHint", true);
    
    addCombo(container, layout, "Target Peak", "targetPeak", 
             {"auto", "100", "200", "400", "600", "1000", "1600"}, "auto");
             
    addCombo(container, layout, "Gamut Mapping", "gamutMapping", 
             {"perceptual", "relative", "saturation", "absolute", "desaturate", "darken", "warn", "linear"}, "perceptual");
             
    addCombo(container, layout, "ICC Profile", "iccProfile", 
             {"(None)", "(Auto)"}, "(None)");
}

void SettingsWindow::buildAnime4KSection()
{
    m_sidebar->addItem("Anime4K");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>Anime4K</h2>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Default Preset", "defaultShaderPreset", {
        "Off",
        "Mode A (HQ)", "Mode B (HQ)", "Mode C (HQ)",
        "Mode A+A (HQ)", "Mode B+B (HQ)", "Mode C+A (HQ)",
        "Mode A (Fast)", "Mode B (Fast)", "Mode C (Fast)",
        "Mode A+A (Fast)", "Mode B+B (Fast)", "Mode C+A (Fast)"
    }, "Off");
}

void SettingsWindow::buildShortcutsSection()
{
    m_sidebar->addItem("Shortcuts");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<h2>Keyboard Shortcuts</h2>", container);
    layout->addWidget(header);

    QLabel *desc = new QLabel("Click any shortcut button below and press a new key combination to change it. Press Escape to cancel.", container);
    desc->setStyleSheet("color: #555; font-size: 12px; margin-bottom: 8px;");
    layout->addWidget(desc);

    // Scrollable area for shortcut definitions
    QScrollArea *scroll = new QScrollArea(container);
    scroll->setWidgetResizable(true);
    scroll->setFrameShape(QFrame::NoFrame);
    scroll->setStyleSheet("QScrollArea { background: transparent; }");
    
    QWidget *gridContainer = new QWidget(scroll);
    gridContainer->setStyleSheet("background: transparent;");
    QGridLayout *gridLayout = new QGridLayout(gridContainer);
    gridLayout->setContentsMargins(0, 0, 0, 0);
    gridLayout->setSpacing(10);
    
    struct ShortcutDef {
        QString key;
        QString description;
        QString defaultKey;
    };
    
    QList<ShortcutDef> shortcutDefs = {
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
        {"OpenSettings", "Open Settings", "Ctrl+,"},
        {"AudioDelayIncrease", "Audio Delay Increase (1ms)", "Ctrl+]"},
        {"AudioDelayDecrease", "Audio Delay Decrease (1ms)", "Ctrl+["}
    };

    int row = 0;
    for (const auto &sh : shortcutDefs) {
        QLabel *lbl = new QLabel(sh.description, gridContainer);
        lbl->setStyleSheet("font-size: 13px; font-weight: 500; color: black;");
        
        QString currentSeq = m_settings.value("shortcut" + sh.key, sh.defaultKey).toString();
        ShortcutButton *btn = new ShortcutButton(sh.key, currentSeq, gridContainer);
        
        connect(btn, &ShortcutButton::shortcutChanged, this, [this](const QString &key, const QString &seq){
            emitSettingChange("shortcut" + key, seq);
        });
        
        gridLayout->addWidget(lbl, row, 0, Qt::AlignLeft | Qt::AlignVCenter);
        gridLayout->addWidget(btn, row, 1, Qt::AlignRight | Qt::AlignVCenter);
        row++;
    }
    
    scroll->setWidget(gridContainer);
    layout->addWidget(scroll, 1);
}
