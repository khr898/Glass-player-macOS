#pragma once

#include <QMainWindow>
#include <QSlider>
#include <QPushButton>
#include <QLabel>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QComboBox>
#include <QSettings>
#include "MpvWidget.h"
#include "WelcomeWindow.h"
#include "SettingsWindow.h"
#include "RcloneBrowser.h"

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow();

    void openFile(const QString &file);
    void setAnime4kPreset(const QString& preset);
    void suppressWelcome();       // Call before show() when a file arg is provided

private slots:
    void onPlayPauseClicked();
    void onOpenClicked();
    void onSettingsClicked();
    void onRcloneClicked();
    void onSliderMoved(int position);
    void onVolumeChanged(int volume);
    void onMuteClicked();
    void onShaderPresetChanged(int index);
    void applySettingToMpv(const QString &key, const QVariant &value);

    void updatePosition(double position);
    void updateDuration(double duration);

    void toggleFullscreen();

    void hideHud();
    void showHud();

    void onRewindClicked();
    void onForwardClicked();
    void onPrevClicked();
    void onNextClicked();
    void onSpeedClicked();
    void onAspectClicked();
    void onSubtitleClicked();
    void onAudioClicked();
    void onUrlClicked();
    void onFullscreenClicked();
    void onBrightnessChanged(int level);

protected:
    void keyPressEvent(QKeyEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;

private:
    void setupUi();
    void setupTopBar();
    void setupBottomBar();
    void setupBrightnessBar();
    void updateHudPositions();
    QString formatTime(double seconds);
    void applyShaderPreset(const QString& preset);

    MpvWidget *m_mpvWidget;
    WelcomeWindow *m_welcomeWindow;
    SettingsWindow *m_settingsWindow;
    RcloneBrowser *m_rcloneBrowser;
    QSettings m_settings;

    // HUD Overlays
    QWidget *m_topBar;
    QWidget *m_bottomBar;
    QWidget *m_brightnessBar;
    QLabel *m_titleLabel;

    // Bottom Bar Elements
    QSlider *m_seekSlider;
    QSlider *m_volumeSlider;
    QSlider *m_brightnessSlider;
    QLabel *m_currentTimeLabel;
    QLabel *m_remainingTimeLabel;

    QPushButton *m_playPauseBtn;
    QPushButton *m_rewindBtn;
    QPushButton *m_forwardBtn;
    QPushButton *m_prevBtn;
    QPushButton *m_nextBtn;

    QPushButton *m_subtitleBtn;
    QPushButton *m_audioBtn;
    QPushButton *m_shaderBtn;
    QPushButton *m_volumeBtn;
    QPushButton *m_speedBtn;
    QPushButton *m_aspectBtn;
    QPushButton *m_fullscreenBtn;

    QTimer *m_hudTimer;

    double m_duration = 0;
    bool m_isPlaying = true;
    bool m_isMuted = false;
    bool m_welcomeSuppressed = false;
};

