#pragma once

#include <QDialog>
#include <QLabel>
#include <QPushButton>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QMimeData>

class WelcomeWindow : public QDialog
{
    Q_OBJECT

public:
    explicit WelcomeWindow(QWidget *parent = nullptr);
    ~WelcomeWindow();

signals:
    void fileOpened(const QString &filePath);
    void openRcloneBrowser();

protected:
    void dragEnterEvent(QDragEnterEvent *event) override;
    void dropEvent(QDropEvent *event) override;

private slots:
    void onOpenFileClicked();
    void onRcloneClicked();

private:
    void setupUi();

    QPushButton *m_openFileBtn;
    QPushButton *m_rcloneBtn;
};
