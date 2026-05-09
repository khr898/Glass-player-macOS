#pragma once

#include <QDialog>
#include <QListWidget>
#include <QStackedWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QCheckBox>
#include <QComboBox>
#include <QLabel>
#include <QSettings>

class SettingsWindow : public QDialog
{
    Q_OBJECT

public:
    explicit SettingsWindow(QWidget *parent = nullptr);
    ~SettingsWindow();

signals:
    void settingChanged(const QString &key, const QVariant &value);

private slots:
    void onSidebarItemChanged(int currentRow);
    void emitSettingChange(const QString &key, const QVariant &value);

private:
    void setupUi();
    void buildGeneralSection();
    void buildVideoSection();
    void buildAudioSection();
    void buildNetworkSection();
    void buildAnime4KSection();

    QWidget* createSectionWidget();
    QCheckBox* addToggle(QWidget *parent, QVBoxLayout *layout, const QString &title, const QString &key, bool defaultValue);
    QComboBox* addCombo(QWidget *parent, QVBoxLayout *layout, const QString &title, const QString &key, const QStringList &options, const QString &defaultValue);

    QListWidget *m_sidebar;
    QStackedWidget *m_contentStack;
    QSettings m_settings;
};
