#include "SettingsWindow.h"
#include <QScrollArea>

SettingsWindow::SettingsWindow(QWidget *parent)
    : QDialog(parent), m_settings("GlassPlayer", "Settings")
{
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

    QLabel *header = new QLabel("<b>General</b>", container);
    layout->addWidget(header);

    addToggle(container, layout, "Show welcome window on launch", "showWelcome", true);
    addToggle(container, layout, "Keep window on top during playback", "keepOnTop", false);
}

void SettingsWindow::buildVideoSection()
{
    m_sidebar->addItem("Video");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<b>Video</b>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Hardware Decoding", "hwdec", {"auto", "auto-safe", "d3d11va", "dxva2", "no"}, "auto-safe");
    addToggle(container, layout, "Enable debanding", "debandEnabled", false);
}

void SettingsWindow::buildAudioSection()
{
    m_sidebar->addItem("Audio");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<b>Audio</b>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Audio Output", "audioOutput", {"wasapi", "openal", "auto"}, "wasapi");
    addCombo(container, layout, "Audio Channels", "audioChannels", {"auto", "auto-safe", "stereo", "5.1", "7.1"}, "auto");
}

void SettingsWindow::buildNetworkSection()
{
    m_sidebar->addItem("Network");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<b>Network</b>", container);
    layout->addWidget(header);

    addToggle(container, layout, "Enable cache", "cacheEnabled", true);
    addCombo(container, layout, "Cache Duration (seconds)", "cacheSecs", {"30", "60", "120", "300"}, "120");
}

void SettingsWindow::buildAnime4KSection()
{
    m_sidebar->addItem("Anime4K");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<b>Anime4K</b>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Default Preset", "defaultShaderPreset", {
        "Off",
        "Mode A (HQ)", "Mode B (HQ)", "Mode C (HQ)",
        "Mode A+A (HQ)", "Mode B+B (HQ)", "Mode C+A (HQ)",
        "Mode A (Fast)", "Mode B (Fast)", "Mode C (Fast)",
        "Mode A+A (Fast)", "Mode B+B (Fast)", "Mode C+A (Fast)"
    }, "Off");
}

void SettingsWindow::buildSubtitlesSection()
{
    m_sidebar->addItem("Subtitles");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<b>Subtitles</b>", container);
    layout->addWidget(header);

    addToggle(container, layout, "Auto-load external subtitles", "subAutoLoad", true);
    addCombo(container, layout, "Font Size", "subFontSize", {"20", "24", "28", "32", "36", "40", "48"}, "36");
    addToggle(container, layout, "Override ASS styles", "subAssOverride", false);
}

void SettingsWindow::buildScalingSection()
{
    m_sidebar->addItem("Scaling");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<b>Scaling & Rendering</b>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Upscale Filter", "scaleFilter", {"ewa_lanczossharp", "lanczos", "spline36", "mitchell", "bilinear"}, "ewa_lanczossharp");
    addCombo(container, layout, "Downscale Filter", "dscaleFilter", {"mitchell", "lanczos", "spline36", "bilinear"}, "mitchell");
}

void SettingsWindow::buildColorSection()
{
    m_sidebar->addItem("Color");
    QWidget *container = createSectionWidget();
    QVBoxLayout *layout = qobject_cast<QVBoxLayout*>(container->layout());

    QLabel *header = new QLabel("<b>Color & HDR</b>", container);
    layout->addWidget(header);

    addCombo(container, layout, "Tone Mapping", "toneMapping", {"auto", "spline", "bt.2390", "reinhard", "mobius"}, "auto");
    addToggle(container, layout, "HDR compute peak", "hdrComputePeak", true);
}

