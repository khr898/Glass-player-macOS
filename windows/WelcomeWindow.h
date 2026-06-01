#pragma once

#include <QDialog>
#include <QLabel>
#include <QPushButton>
#include <QToolButton>
#include <QFrame>
#include <QDragEnterEvent>
#include <QDropEvent>
#include <QMimeData>
#include <QMouseEvent>

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
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;

private slots:
    void onOpenFileClicked();
    void onRcloneClicked();

private:
    void setupUi();

    QFrame *m_mainFrame = nullptr;
    QPushButton *m_closeBtn = nullptr;
    QToolButton *m_openFileBtn = nullptr;
    QToolButton *m_rcloneBtn = nullptr;
    bool m_dragActive = false;
    QPoint m_dragPosition;
};
