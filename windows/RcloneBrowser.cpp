#include "RcloneBrowser.h"
#include <QRegularExpression>
#include <QDebug>
#include <QUrl>

RcloneBrowser::RcloneBrowser(QWidget *parent)
    : QDialog(parent), m_networkManager(new QNetworkAccessManager(this))
{
    setupUi();
}

RcloneBrowser::~RcloneBrowser()
{
}

void RcloneBrowser::setupUi()
{
    setWindowTitle("Remote Browser");
    setMinimumSize(520, 600);

    QVBoxLayout *mainLayout = new QVBoxLayout(this);

    // Connection Bar
    QHBoxLayout *connLayout = new QHBoxLayout();
    m_urlField = new QLineEdit(this);
    m_urlField->setPlaceholderText("http://localhost:8080");
    m_connectBtn = new QPushButton("Connect", this);
    connect(m_connectBtn, &QPushButton::clicked, this, &RcloneBrowser::onConnectClicked);
    
    connLayout->addWidget(m_urlField);
    connLayout->addWidget(m_connectBtn);
    mainLayout->addLayout(connLayout);

    // Nav Bar
    QHBoxLayout *navLayout = new QHBoxLayout();
    m_backBtn = new QPushButton("<", this);
    m_upBtn = new QPushButton("^", this);
    m_refreshBtn = new QPushButton("R", this);
    
    m_backBtn->setFixedWidth(30);
    m_upBtn->setFixedWidth(30);
    m_refreshBtn->setFixedWidth(30);

    connect(m_backBtn, &QPushButton::clicked, this, &RcloneBrowser::onBackClicked);
    connect(m_upBtn, &QPushButton::clicked, this, &RcloneBrowser::onUpClicked);
    connect(m_refreshBtn, &QPushButton::clicked, this, &RcloneBrowser::onRefreshClicked);

    m_backBtn->setEnabled(false);
    m_upBtn->setEnabled(false);
    m_refreshBtn->setEnabled(false);

    navLayout->addWidget(m_backBtn);
    navLayout->addWidget(m_upBtn);
    navLayout->addWidget(m_refreshBtn);
    navLayout->addStretch();
    mainLayout->addLayout(navLayout);

    // List View
    m_listWidget = new QListWidget(this);
    connect(m_listWidget, &QListWidget::itemDoubleClicked, this, &RcloneBrowser::onItemDoubleClicked);
    mainLayout->addWidget(m_listWidget);
}

void RcloneBrowser::onConnectClicked()
{
    QString url = m_urlField->text().trimmed();
    if (url.isEmpty()) return;

    if (!url.contains("://")) {
        url = "http://" + url;
    }
    while (url.endsWith("/")) {
        url.chop(1);
    }

    m_baseUrl = url;
    m_currentPath = "/";
    m_pathHistory.clear();
    m_isConnected = true;

    m_connectBtn->setText("Reconnect");
    m_refreshBtn->setEnabled(true);
    
    fetchDirectory();
}

void RcloneBrowser::onBackClicked()
{
    if (m_pathHistory.isEmpty()) return;
    m_currentPath = m_pathHistory.takeLast();
    fetchDirectory();
}

void RcloneBrowser::onUpClicked()
{
    if (m_currentPath == "/") return;
    m_pathHistory.append(m_currentPath);
    
    QStringList parts = m_currentPath.split("/", Qt::SkipEmptyParts);
    if (!parts.isEmpty()) {
        parts.removeLast();
    }
    
    if (parts.isEmpty()) {
        m_currentPath = "/";
    } else {
        m_currentPath = "/" + parts.join("/") + "/";
    }
    fetchDirectory();
}

void RcloneBrowser::onRefreshClicked()
{
    if (!m_isConnected) return;
    fetchDirectory();
}

void RcloneBrowser::onItemDoubleClicked(QListWidgetItem *item)
{
    QString href = item->data(Qt::UserRole).toString();
    bool isDir = item->data(Qt::UserRole + 1).toBool();

    if (isDir) {
        m_pathHistory.append(m_currentPath);
        m_currentPath = m_currentPath + href;
        fetchDirectory();
    } else {
        QString fullUrl = m_baseUrl + m_currentPath + href;
        emit fileSelected(fullUrl);
        accept();
    }
}

void RcloneBrowser::fetchDirectory()
{
    if (m_currentReply) {
        m_currentReply->abort();
        m_currentReply->deleteLater();
        m_currentReply = nullptr;
    }

    m_backBtn->setEnabled(!m_pathHistory.isEmpty());
    m_upBtn->setEnabled(m_currentPath != "/");

    m_listWidget->clear();
    m_listWidget->addItem("Loading...");

    QString urlString = m_baseUrl + m_currentPath;
    QNetworkRequest request((QUrl(urlString)));
    m_currentReply = m_networkManager->get(request);
    connect(m_currentReply, &QNetworkReply::finished, this, [this]() {
        onNetworkReply(m_currentReply);
    });
}

void RcloneBrowser::onNetworkReply(QNetworkReply *reply)
{
    m_currentReply = nullptr;
    if (reply->error() != QNetworkReply::NoError) {
        if (reply->error() != QNetworkReply::OperationCanceledError) {
            m_listWidget->clear();
            m_listWidget->addItem("Error connecting to server.");
        }
        reply->deleteLater();
        return;
    }

    QString html = QString::fromUtf8(reply->readAll());
    parseDirectoryListing(html);
    reply->deleteLater();
}

void RcloneBrowser::parseDirectoryListing(const QString &html)
{
    m_listWidget->clear();
    
    // Simple regex for `<a href="link">name</a> size`
    QRegularExpression regex("<a\\s+href=\"([^\"]+)\"\\s*>([^<]+)</a>\\s*([^<]*)");
    QRegularExpressionMatchIterator i = regex.globalMatch(html);
    
    while (i.hasNext()) {
        QRegularExpressionMatch match = i.next();
        QString href = match.captured(1);
        QString name = match.captured(2).trimmed();
        QString size = match.captured(3).trimmed();
        
        if (href == "../" || href == ".." || href == "/" || href == "./") continue;
        
        bool isDir = href.endsWith("/");
        
        QListWidgetItem *item = new QListWidgetItem();
        if (isDir) {
            item->setText("[DIR] " + name);
        } else {
            item->setText(name + "  (" + size + ")");
        }
        
        item->setData(Qt::UserRole, href);
        item->setData(Qt::UserRole + 1, isDir);
        m_listWidget->addItem(item);
    }
    
    if (m_listWidget->count() == 0) {
        m_listWidget->addItem("Empty directory");
    }
}
