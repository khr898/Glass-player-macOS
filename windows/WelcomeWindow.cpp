#include "WelcomeWindow.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFileDialog>
#include <QGraphicsDropShadowEffect>
#include <QIcon>
#include <QApplication>

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
        "QFrame#mainFrame { "
        "  background: qlineargradient(spread:pad, x1:0, y1:0, x2:0, y2:1, "
        "                              stop:0 rgba(28, 28, 38, 245), "
        "                              stop:1 rgba(15, 15, 20, 250)); "
        "  border: 1px solid rgba(255, 255, 255, 30); "
        "  border-radius: 20px; "
        "}"
    );

    // Breathtaking Drop Shadow Effect
    QGraphicsDropShadowEffect *shadow = new QGraphicsDropShadowEffect(this);
    shadow->setBlurRadius(24);
    shadow->setXOffset(0);
    shadow->setYOffset(8);
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
    
    m_closeBtn = new QPushButton("✕", m_mainFrame);
    m_closeBtn->setObjectName("closeBtn");
    m_closeBtn->setCursor(Qt::PointingHandCursor);
    m_closeBtn->setStyleSheet(
        "QPushButton#closeBtn { "
        "  background: transparent; "
        "  color: rgba(255, 255, 255, 130); "
        "  border: none; "
        "  font-size: 14px; "
        "  font-weight: bold; "
        "  min-width: 26px; "
        "  max-width: 26px; "
        "  min-height: 26px; "
        "  max-height: 26px; "
        "  border-radius: 13px; "
        "  margin-top: -2px; "
        "  margin-right: -2px; "
        "} "
        "QPushButton#closeBtn:hover { "
        "  background-color: rgba(232, 17, 35, 220); "
        "  color: white; "
        "} "
        "QPushButton#closeBtn:pressed { "
        "  background-color: rgba(232, 17, 35, 160); "
        "}"
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
        "QLabel#appIconLabel { "
        "  background-color: rgba(255, 255, 255, 10); "
        "  border: 1px solid rgba(255, 255, 255, 36); "
        "  border-radius: 18px; "
        "  padding: 8px; "
        "}"
    );
    
    mainLayout->addWidget(iconLabel, 0, Qt::AlignHCenter);
    mainLayout->addSpacing(12);

    // ── Modern Bold Title ──
    QLabel *titleLabel = new QLabel("Glass Player", m_mainFrame);
    titleLabel->setAlignment(Qt::AlignCenter);
    titleLabel->setStyleSheet(
        "QLabel { "
        "  color: #ffffff; "
        "  font-family: 'Segoe UI', -apple-system, sans-serif; "
        "  font-size: 24px; "
        "  font-weight: 700; "
        "  letter-spacing: 0.5px; "
        "  background: transparent; "
        "}"
    );
    mainLayout->addWidget(titleLabel);

    // ── Organic Subtitle ──
    QLabel *subtitleLabel = new QLabel("Drop a video file here, or choose an option below", m_mainFrame);
    subtitleLabel->setAlignment(Qt::AlignCenter);
    subtitleLabel->setStyleSheet(
        "QLabel { "
        "  color: rgba(255, 255, 255, 140); "
        "  font-family: 'Segoe UI', -apple-system, sans-serif; "
        "  font-size: 13px; "
        "  font-weight: 400; "
        "  background: transparent; "
        "}"
    );
    mainLayout->addWidget(subtitleLabel);
    
    mainLayout->addSpacing(28);

    // ── Premium Actions Layout ──
    QHBoxLayout *buttonsLayout = new QHBoxLayout();
    buttonsLayout->setAlignment(Qt::AlignCenter);
    buttonsLayout->setSpacing(24);

    QString buttonStyle = 
        "QToolButton { "
        "  background-color: rgba(255, 255, 255, 14); "
        "  color: #ffffff; "
        "  border: 1px solid rgba(255, 255, 255, 24); "
        "  border-radius: 16px; "
        "  font-family: 'Segoe UI', -apple-system, sans-serif; "
        "  font-size: 13px; "
        "  font-weight: 600; "
        "  padding-top: 18px; "
        "  padding-bottom: 14px; "
        "} "
        "QToolButton:hover { "
        "  background-color: rgba(255, 255, 255, 28); "
        "  border: 1px solid rgba(255, 255, 255, 48); "
        "} "
        "QToolButton:pressed { "
        "  background-color: rgba(255, 255, 255, 18); "
        "  border: 1px solid rgba(255, 255, 255, 32); "
        "}";

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
        event->acceptProposedAction();
    }
}

void WelcomeWindow::dropEvent(QDropEvent *event)
{
    const QMimeData *mimeData = event->mimeData();
    if (mimeData->hasUrls()) {
        QList<QUrl> urlList = mimeData->urls();
        if (!urlList.isEmpty()) {
            QString filePath = urlList.first().toLocalFile();
            emit fileOpened(filePath);
            accept();
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
    QString file = QFileDialog::getOpenFileName(this, "Open Video");
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
