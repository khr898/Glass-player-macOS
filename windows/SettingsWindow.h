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
#include <QPushButton>
#include <QKeyEvent>
#include <QKeySequence>

#include "Theme.h"

class ShortcutButton : public QPushButton
{
    Q_OBJECT
public:
    explicit ShortcutButton(const QString &actionKey, const QString &currentSequence, QWidget *parent = nullptr)
        : QPushButton(currentSequence, parent), m_actionKey(actionKey), m_sequence(currentSequence), m_capturing(false)
    {
        setCursor(Qt::PointingHandCursor);
        setFixedWidth(150);
        setStyleSheet(
            QString(
                "QPushButton { background: %1; border: 1px solid %2; border-radius: 4px; padding: 4px 8px; font-weight: bold; color: %3; }"
                "QPushButton:hover { background: %4; border-color: %5; }"
                "QPushButton:checked { background: %6; color: #1c1c1c; border-color: %6; }"
            ).arg(Theme::kBgSurfaceSecondary, Theme::kBorderDefault, Theme::kTextPrimary, Theme::kBgHover, Theme::kBorderElevated, Theme::kAccent)
        );
        setCheckable(true);
        connect(this, &QPushButton::toggled, this, &ShortcutButton::onToggled);
    }

signals:
    void shortcutChanged(const QString &key, const QString &newSequence);

protected:
    void onToggled(bool checked)
    {
        m_capturing = checked;
        if (m_capturing) {
            setText("Press Key...");
            setFocus();
        } else {
            setText(m_sequence);
        }
    }

    void keyPressEvent(QKeyEvent *event) override
    {
        if (m_capturing) {
            int key = event->key();
            if (key == Qt::Key_Escape) {
                setChecked(false);
                return;
            }

            Qt::KeyboardModifiers modifiers = event->modifiers();
            QKeySequence seq(key | modifiers);
            QString seqStr = seq.toString();
            
            if (!seqStr.isEmpty()) {
                m_sequence = seqStr;
                setText(seqStr);
                setChecked(false);
                emit shortcutChanged(m_actionKey, seqStr);
            }
            event->accept();
            return;
        }
        QPushButton::keyPressEvent(event);
    }

private:
    QString m_actionKey;
    QString m_sequence;
    bool m_capturing;
};

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

protected:
    void changeEvent(QEvent *event) override;

private:
    void setupUi();
    void buildGeneralSection();
    void buildVideoSection();
    void buildAudioSection();
    void buildSubtitlesSection();
    void buildNetworkSection();
    void buildScalingSection();
    void buildColorSection();
    void buildAnime4KSection();
    void buildShortcutsSection();

    QWidget* createSectionWidget();
    QCheckBox* addToggle(QWidget *parent, QVBoxLayout *layout, const QString &title, const QString &key, bool defaultValue);
    QComboBox* addCombo(QWidget *parent, QVBoxLayout *layout, const QString &title, const QString &key, const QStringList &options, const QString &defaultValue);

    QListWidget *m_sidebar;
    QStackedWidget *m_contentStack;
    QSettings m_settings;
};
