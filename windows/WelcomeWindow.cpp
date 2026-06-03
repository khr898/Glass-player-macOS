#include "WelcomeWindow.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFileDialog>
#include <QGraphicsDropShadowEffect>
#include <QIcon>
#include <QApplication>
#include <QFileInfo>
#include <QMimeData>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QPropertyAnimation>
#include <QShowEvent>
#include "Theme.h"

static bool isPlayableFile(const QString& filePath) {
    if (filePath.contains("://")) {
        return true;
    }
    static const QStringList kSupportedExtensions = {
        "mp4", "mkv", "avi", "mov", "flv", "webm", "wmv", "m4v", "3gp", "ts", "mts", "m2ts", "vob", "ogv", "asf",
        "mp3", "m4a", "aac", "flac", "wav", "ac3", "dts", "ogg", "opus", "wma", "mka"
    };
    QFileInfo info(filePath);
    QString ext = info.suffix().toLower();
    return kSupportedExtensions.contains(ext);
}

WelcomeWindow::WelcomeWindow(QWidget *parent)
    : QDialog(parent)
{
    setAcceptDrops(true);
    setupUi();
}

WelcomeWindow::~WelcomeWindow()
{
}

void WelcomeWindow::setupUi()
{
    setWindowTitle("Glass Player");
    
    // Size accommodates both the content frame and the drop shadow margins
    setFixedSize(520, 390);

    // Make window frameless, top-level dialog, and translucent
    setWindowFlags(Qt::Dialog | Qt::FramelessWindowHint | Qt::WindowSystemMenuHint);
    setAttribute(Qt::WA_TranslucentBackground);

    // Dialog layout leaves a gap for the drop shadow to render
    QVBoxLayout *dialogLayout = new QVBoxLayout(this);
    dialogLayout->setContentsMargins(15, 15, 15, 15);

    // Primary Container (Glass Card)
    m_mainFrame = new QFrame(this);
    m_mainFrame->setObjectName("mainFrame");
    m_mainFrame->setStyleSheet(
        QString(
            "QFrame#mainFrame { "
            "  background-color: %1; "
            "  border: 1px solid %2; "
            "  border-radius: 8px; "
            "}"
        ).arg(Theme::kBgSurface, Theme::kBorderElevated)
    );

    // Breathtaking Drop Shadow Effect
    QGraphicsDropShadowEffect *shadow = new QGraphicsDropShadowEffect(m_mainFrame);
    shadow->setBlurRadius(16);
    shadow->setXOffset(0);
    shadow->setYOffset(4);
    shadow->setColor(QColor(0, 0, 0, 180));
    m_mainFrame->setGraphicsEffect(shadow);

    dialogLayout->addWidget(m_mainFrame);

    // Inner layout for controls
    QVBoxLayout *mainLayout = new QVBoxLayout(m_mainFrame);
    mainLayout->setAlignment(Qt::AlignTop);
    mainLayout->setContentsMargins(24, 16, 24, 24);
    mainLayout->setSpacing(0);

    // ── Sleek Custom Title Bar Row ──
    QHBoxLayout *titleBarLayout = new QHBoxLayout();
    titleBarLayout->setContentsMargins(0, 0, 0, 0);
    
    m_closeBtn = new QPushButton("⨉", m_mainFrame);
    m_closeBtn->setObjectName("closeBtn");
    m_closeBtn->setCursor(Qt::PointingHandCursor);
    m_closeBtn->setStyleSheet(
        QString(
            "QPushButton#closeBtn { "
            "  background: transparent; "
            "  color: %1; "
            "  border: none; "
            "  font-size: 14px; "
            "  font-weight: bold; "
            "  min-width: 32px; "
            "  max-width: 32px; "
            "  min-height: 32px; "
            "  max-height: 32px; "
            "  border-radius: 4px; "
            "  margin-top: -2px; "
            "  margin-right: -2px; "
            "} "
            "QPushButton#closeBtn:hover { "
            "  background-color: %2; "
            "  color: #ffffff; "
            "} "
            "QPushButton#closeBtn:pressed { "
            "  background-color: %3; "
            "  color: #ffffff; "
            "}"
        ).arg(Theme::kTextSecondary, Theme::kCloseHover, Theme::kClosePressed)
    );
    connect(m_closeBtn, &QPushButton::clicked, this, &WelcomeWindow::reject);
    
    titleBarLayout->addStretch();
    titleBarLayout->addWidget(m_closeBtn);
    mainLayout->addLayout(titleBarLayout);

    // ── App Icon Centerpiece ──
    QLabel *iconLabel = new QLabel(m_mainFrame);
    iconLabel->setObjectName("appIconLabel");
    iconLabel->setFixedSize(72, 72);
    iconLabel->setAlignment(Qt::AlignCenter);
    
    // Scale vector graphic sharply
    QIcon appIcon(":/icons/app.svg");
    if (!appIcon.isNull()) {
        iconLabel->setPixmap(appIcon.pixmap(52, 52));
    }
    
    iconLabel->setStyleSheet(
        QString(
            "QLabel#appIconLabel { "
            "  background-color: %1; "
            "  border: 1px solid %2; "
            "  border-radius: 12px; "
            "  padding: 8px; "
            "}"
        ).arg(Theme::kBgSurfaceSecondary, Theme::kBorderDefault)
    );
    
    mainLayout->addWidget(iconLabel, 0, Qt::AlignHCenter);
    mainLayout->addSpacing(12);

    // ── Modern Bold Title ──
    QLabel *titleLabel = new QLabel("Glass Player", m_mainFrame);
    titleLabel->setAlignment(Qt::AlignCenter);
    titleLabel->setStyleSheet(
        QString(
            "QLabel { "
            "  color: %1; "
            "  font-family: %2; "
            "  font-size: 22px; "
            "  font-weight: 600; "
            "  letter-spacing: 0.5px; "
            "  background: transparent; "
            "}"
        ).arg(Theme::kTextPrimary, Theme::kFontFamily)
    );
    mainLayout->addWidget(titleLabel);

    // ── Organic Subtitle ──
    QLabel *subtitleLabel = new QLabel("Drop a video file here, or choose an option below", m_mainFrame);
    subtitleLabel->setAlignment(Qt::AlignCenter);
    subtitleLabel->setStyleSheet(
        QString(
            "QLabel { "
            "  color: %1; "
            "  font-family: %2; "
            "  font-size: 13px; "
            "  font-weight: 400; "
            "  background: transparent; "
            "}"
        ).arg(Theme::kTextSecondary, Theme::kFontFamily)
    );
    mainLayout->addWidget(subtitleLabel);
    
    mainLayout->addSpacing(28);

    // ── Premium Actions Layout ──
    QHBoxLayout *buttonsLayout = new QHBoxLayout();
    buttonsLayout->setAlignment(Qt::AlignCenter);
    buttonsLayout->setSpacing(24);

    QString buttonStyle = 
        QString(
            "QToolButton { "
            "  background-color: %1; "
            "  color: %2; "
            "  border: 1px solid %3; "
            "  border-radius: 8px; "
            "  font-family: %4; "
            "  font-size: 13px; "
            "  font-weight: 600; "
            "  padding-top: 18px; "
            "  padding-bottom: 14px; "
            "} "
            "QToolButton:hover { "
            "  background-color: %5; "
            "  border: 1px solid %6; "
            "} "
            "QToolButton:pressed { "
            "  background-color: %7; "
            "  border: 1px solid %8; "
            "}"
        ).arg(Theme::kBgSurfaceSecondary, Theme::kTextPrimary, Theme::kBorderDefault, Theme::kFontFamily,
              Theme::kBgHover, Theme::kBorderElevated, Theme::kBgPressed, Theme::kBorderDefault);

    // 1. Open File Card Button
    m_openFileBtn = new QToolButton(m_mainFrame);
    m_openFileBtn->setText("Open File");
    m_openFileBtn->setIcon(QIcon(":/icons/open_file.svg"));
    m_openFileBtn->setIconSize(QSize(28, 28));
    m_openFileBtn->setToolButtonStyle(Qt::ToolButtonTextUnderIcon);
    m_openFileBtn->setFixedSize(180, 100);
    m_openFileBtn->setCursor(Qt::PointingHandCursor);
    m_openFileBtn->setStyleSheet(buttonStyle);
    connect(m_openFileBtn, &QToolButton::clicked, this, &WelcomeWindow::onOpenFileClicked);

    // 2. Remote Cloud Browser Card Button
    m_rcloneBtn = new QToolButton(m_mainFrame);
    m_rcloneBtn->setText("Remote Browser");
    m_rcloneBtn->setIcon(QIcon(":/icons/remote.svg"));
    m_rcloneBtn->setIconSize(QSize(28, 28));
    m_rcloneBtn->setToolButtonStyle(Qt::ToolButtonTextUnderIcon);
    m_rcloneBtn->setFixedSize(180, 100);
    m_rcloneBtn->setCursor(Qt::PointingHandCursor);
    m_rcloneBtn->setStyleSheet(buttonStyle);
    connect(m_rcloneBtn, &QToolButton::clicked, this, &WelcomeWindow::onRcloneClicked);

    buttonsLayout->addWidget(m_openFileBtn);
    buttonsLayout->addWidget(m_rcloneBtn);

    mainLayout->addLayout(buttonsLayout);
    mainLayout->addSpacing(8);
}

// ── Drag & Drop Implementation ──
void WelcomeWindow::dragEnterEvent(QDragEnterEvent *event)
{
    if (event->mimeData()->hasUrls()) {
        QList<QUrl> urls = event->mimeData()->urls();
        if (!urls.isEmpty()) {
            QString filePath = urls.first().toLocalFile();
            if (isPlayableFile(filePath)) {
                event->acceptProposedAction();
                return;
            }
        }
    }
    event->ignore();
}

void WelcomeWindow::dropEvent(QDropEvent *event)
{
    const QMimeData *mimeData = event->mimeData();
    if (mimeData->hasUrls()) {
        QList<QUrl> urlList = mimeData->urls();
        if (!urlList.isEmpty()) {
            QString filePath = urlList.first().toLocalFile();
            if (isPlayableFile(filePath)) {
                emit fileOpened(filePath);
                accept();
            }
        }
    }
}

// ── Frameless Windows Movement ──
void WelcomeWindow::mousePressEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton) {
        m_dragActive = true;
        m_dragPosition = event->globalPosition().toPoint() - frameGeometry().topLeft();
        event->accept();
    }
}

void WelcomeWindow::mouseMoveEvent(QMouseEvent *event)
{
    if (m_dragActive && (event->buttons() & Qt::LeftButton)) {
        move(event->globalPosition().toPoint() - m_dragPosition);
        event->accept();
    }
}

void WelcomeWindow::mouseReleaseEvent(QMouseEvent *event)
{
    m_dragActive = false;
}

// ── Slots ──
void WelcomeWindow::onOpenFileClicked()
{
    QString file = QFileDialog::getOpenFileName(this, "Open Video", "",
        "Media Files (*.mp4 *.mkv *.avi *.mov *.flv *.webm *.wmv *.m4v *.3gp *.ts *.mts *.m2ts *.vob *.ogv *.asf *.mp3 *.m4a *.aac *.flac *.wav *.ac3 *.dts *.ogg *.opus *.wma *.mka);;Video Files (*.mp4 *.mkv *.avi *.mov *.flv *.webm *.wmv *.m4v *.3gp *.ts *.mts *.m2ts *.vob *.ogv *.asf);;Audio Files (*.mp3 *.m4a *.aac *.flac *.wav *.ac3 *.dts *.ogg *.opus *.wma *.mka);;All Files (*.*)");
    if (!file.isEmpty()) {
        emit fileOpened(file);
        accept();
    }
}

void WelcomeWindow::onRcloneClicked()
{
    emit openRcloneBrowser();
    accept();
}

void WelcomeWindow::showEvent(QShowEvent *event)
{
    QDialog::showEvent(event);
    QPropertyAnimation *anim = new QPropertyAnimation(this, "windowOpacity");
    anim->setDuration(200);
    anim->setStartValue(0.0);
    anim->setEndValue(1.0);
    anim->start(QAbstractAnimation::DeleteWhenStopped);
}
