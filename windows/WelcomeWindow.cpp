#include "WelcomeWindow.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFileDialog>

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
    setFixedSize(480, 340);

    QVBoxLayout *mainLayout = new QVBoxLayout(this);
    mainLayout->setAlignment(Qt::AlignCenter);

    QLabel *titleLabel = new QLabel("Glass Player", this);
    QFont titleFont = titleLabel->font();
    titleFont.setPointSize(22);
    titleFont.setBold(true);
    titleLabel->setFont(titleFont);
    titleLabel->setAlignment(Qt::AlignCenter);

    QLabel *subtitleLabel = new QLabel("Drop a video file here, or choose an option below", this);
    subtitleLabel->setAlignment(Qt::AlignCenter);
    subtitleLabel->setStyleSheet("color: gray;");

    mainLayout->addSpacing(30);
    mainLayout->addWidget(titleLabel);
    mainLayout->addWidget(subtitleLabel);
    mainLayout->addSpacing(30);

    QHBoxLayout *buttonsLayout = new QHBoxLayout();
    buttonsLayout->setAlignment(Qt::AlignCenter);
    buttonsLayout->setSpacing(20);

    m_openFileBtn = new QPushButton("Open File\n\nBrowse local files", this);
    m_openFileBtn->setFixedSize(170, 90);
    connect(m_openFileBtn, &QPushButton::clicked, this, &WelcomeWindow::onOpenFileClicked);

    m_rcloneBtn = new QPushButton("Remote Browser\n\nStream from remote storage", this);
    m_rcloneBtn->setFixedSize(170, 90);
    connect(m_rcloneBtn, &QPushButton::clicked, this, &WelcomeWindow::onRcloneClicked);

    buttonsLayout->addWidget(m_openFileBtn);
    buttonsLayout->addWidget(m_rcloneBtn);

    mainLayout->addLayout(buttonsLayout);
    mainLayout->addSpacing(30);
}

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
