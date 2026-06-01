#pragma once

#include <QMainWindow>
#include <QSlider>
#include <QPushButton>
#include <QLabel>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QComboBox>
#include <QLineEdit>
#include <QSettings>
#include <QMouseEvent>
#include "MpvWidget.h"
#include "WelcomeWindow.h"
#include "SettingsWindow.h"
#include "RcloneBrowser.h"

class ClickableSlider : public QSlider
{
    Q_OBJECT
public:
    explicit ClickableSlider(Qt::Orientation orientation, QWidget *parent = nullptr)
        : QSlider(orientation, parent)
    {
    }

protected:
    void mousePressEvent(QMouseEvent *event) override
    {
        if (event->button() == Qt::LeftButton) {
            double ratio = 0.0;
            if (orientation() == Qt::Horizontal) {
                ratio = static_cast<double>(event->pos().x()) / width();
            } else {
                ratio = 1.0 - (static_cast<double>(event->pos().y()) / height());
            }
            int val = minimum() + qRound(ratio * (maximum() - minimum()));
            val = qBound(minimum(), val, maximum());
            setValue(val);
            emit sliderMoved(val);
        }
        QSlider::mousePressEvent(event);
    }
};

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow();

    void openFile(const QString &file);
    void setAnime4kPreset(const QString& preset);
    void suppressWelcome();       // Call before show() when a file arg is provided
    bool shouldShowWelcome() const;
    int runWelcomeScreen();

    struct TrackInfo {
        int id;
        QString type; // "video", "audio", "sub"
        QString label;
        bool selected;
    };

    struct ShortcutInfo {
        QString key;
        QString description;
        QString defaultKey;
    };
    static QList<ShortcutInfo> getShortcutDefinitions();

    QList<TrackInfo> getTracks();
    void setSubtitleTrack(int id);
    void setAudioTrack(int id);
    void addExternalSubtitle();
    void addExternalAudio();
    void executeCommand(const QString &commandLine);

private slots:
    void onPlayPauseClicked();
    void onOpenClicked();
    void onSettingsClicked();
    void onFileLoaded();
    void onRcloneClicked();
    void onSliderMoved(int position);
    void onVolumeChanged(int volume);
    void onMuteClicked();

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
    void onShaderClicked();
    void onUrlClicked();
    void onUrlSubmitted();
    void onFullscreenClicked();
    void onBrightnessChanged(int level);

protected:
    void keyPressEvent(QKeyEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void changeEvent(QEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void mouseDoubleClickEvent(QMouseEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void setupUi();
    void setupTopBar();
    void setupBottomBar();
    void setupBrightnessBar();
    void setupVolumeBar();
    void updateHudPositions();
    void syncSystemControls();
    void updateVolumeIcon(int volume, bool muted);
    QString formatTime(double seconds);
    void applyShaderPreset(const QString& preset);
    void updateHoverBars();
    void applyScrollDelta(int delta, double xPos);

    MpvWidget *m_mpvWidget;
    QWidget *m_centralWidget;
    WelcomeWindow *m_welcomeWindow;
    SettingsWindow *m_settingsWindow;
    RcloneBrowser *m_rcloneBrowser;
    QSettings m_settings;

    // HUD Overlays
    QWidget *m_topBar;
    QWidget *m_bottomBar;
    QWidget *m_brightnessBar;
    QWidget *m_volumeBar;
    QLabel *m_titleLabel;
    QLineEdit *m_urlEdit;

    // Bottom Bar Elements
    ClickableSlider *m_seekSlider;
    ClickableSlider *m_volumeSlider;
    ClickableSlider *m_brightnessSlider;
    ClickableSlider *m_volumeHoverSlider;
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
    QTimer *m_systemSyncTimer;
    QTimer *m_clickTimer;

    double m_duration = 0;
    bool m_isPlaying = true;
    bool m_isMuted = false;
    bool m_welcomeSuppressed = false;
    bool m_syncingFromSystem = false;
    bool m_firstFileLoaded = true;

    void handleShortcutTrigger(const QString &action);
    void cycleSubtitleTrack();
    void cycleAudioTrack();
    void cycleAspectOverride();
    void cycleShaderPreset();
    void adjustAudioDelay(double deltaSeconds);
    QHash<QString, class QShortcut*> m_shortcuts;

    // Timeline preview, smooth scrub, and hover
    void handleTimelineHover(QPoint pos);
    void hideTimelinePreview();
    void generateThumbnail(double time, int cacheKey);
    void onSliderReleased();

    class TimelinePreviewWidget *m_previewWidget = nullptr;
    class ThumbnailMpv *m_thumbnailMpv = nullptr;
    QString m_currentFile;
    QHash<int, QImage> m_thumbnailCache;
    bool m_isGeneratingThumbnail = false;
    double m_pendingThumbnailTime = -1;
    double m_lastHoverTime = 0;
    bool m_isSeeking = false;
    qint64 m_lastSeekTime = 0;
};

