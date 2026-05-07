#pragma once

#include <QMainWindow>
#include <QSlider>
#include <QPushButton>
#include <QLabel>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QComboBox>
#include "MpvWidget.h"

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow();

    void openFile(const QString &file);

private slots:
    void onPlayPauseClicked();
    void onOpenClicked();
    void onSliderMoved(int position);
    void onVolumeChanged(int volume);
    void onMuteClicked();
    void onShaderPresetChanged(int index);

    void updatePosition(double position);
    void updateDuration(double duration);

    void toggleFullscreen();

protected:
    void keyPressEvent(QKeyEvent *event) override;

private:
    void setupUi();
    QString formatTime(double seconds);
    void applyShaderPreset(const QString& preset);

    MpvWidget *m_mpvWidget;

    QSlider *m_seekSlider;
    QSlider *m_volumeSlider;
    QPushButton *m_playPauseBtn;
    QPushButton *m_muteBtn;
    QLabel *m_timeLabel;
    QComboBox *m_shaderCombo;

    double m_duration = 0;
    bool m_isPlaying = true;
};
