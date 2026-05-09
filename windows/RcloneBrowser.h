#pragma once

#include <QDialog>
#include <QLineEdit>
#include <QPushButton>
#include <QListWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class RcloneBrowser : public QDialog
{
    Q_OBJECT

public:
    explicit RcloneBrowser(QWidget *parent = nullptr);
    ~RcloneBrowser();

signals:
    void fileSelected(const QString &url);

private slots:
    void onConnectClicked();
    void onBackClicked();
    void onUpClicked();
    void onRefreshClicked();
    void onItemDoubleClicked(QListWidgetItem *item);
    void onNetworkReply(QNetworkReply *reply);

private:
    void setupUi();
    void fetchDirectory();
    void parseDirectoryListing(const QString &html);

    QLineEdit *m_urlField;
    QPushButton *m_connectBtn;
    QPushButton *m_backBtn;
    QPushButton *m_upBtn;
    QPushButton *m_refreshBtn;
    QListWidget *m_listWidget;

    QNetworkAccessManager *m_networkManager;
    QNetworkReply *m_currentReply = nullptr;

    QString m_baseUrl;
    QString m_currentPath;
    QStringList m_pathHistory;
    bool m_isConnected = false;
};
