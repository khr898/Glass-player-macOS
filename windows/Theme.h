#pragma once
#include <QString>

namespace Theme {
    // Colors
    inline const QString kBgSurface = "rgba(32, 32, 32, 230)";
    inline const QString kBgSurfaceSecondary = "rgba(255, 255, 255, 15)";
    inline const QString kBgHover = "rgba(255, 255, 255, 23)";
    inline const QString kBgPressed = "rgba(255, 255, 255, 13)";
    inline const QString kBorderDefault = "rgba(255, 255, 255, 30)";
    inline const QString kBorderElevated = "rgba(255, 255, 255, 46)";
    inline const QString kAccent = "#60CDFF";
    inline const QString kAccentSubtle = "rgba(96, 205, 255, 51)";
    inline const QString kTextPrimary = "rgba(255, 255, 255, 237)";
    inline const QString kTextSecondary = "rgba(255, 255, 255, 156)";
    inline const QString kTextTertiary = "rgba(255, 255, 255, 115)";
    inline const QString kSliderTrack = "rgba(255, 255, 255, 46)";
    inline const QString kSliderFill = "#60CDFF";
    inline const QString kCloseHover = "#C42B1C";
    inline const QString kClosePressed = "#B01A10";

    // Fonts
    inline const QString kFontFamily = "\"Segoe UI Variable\", \"Segoe UI\", -apple-system, BlinkMacSystemFont, Roboto, sans-serif";
    inline const QString kFontMono = "\"Cascadia Mono\", Consolas, monospace";

    // Stylesheets
    inline const QString kMenuStyle =
        "QMenu {"
        "  background-color: rgba(32, 32, 32, 240);"
        "  border: 1px solid rgba(255, 255, 255, 46);"
        "  border-radius: 8px;"
        "  padding: 6px 0px;"
        "}"
        "QMenu::item {"
        "  padding: 6px 24px 6px 20px;"
        "  background-color: transparent;"
        "  color: rgba(255, 255, 255, 237);"
        "  font-family: \"Segoe UI Variable\", \"Segoe UI\", sans-serif;"
        "  font-size: 13px;"
        "}"
        "QMenu::item:selected {"
        "  background-color: rgba(96, 205, 255, 51);"
        "  color: #60CDFF;"
        "  border-radius: 4px;"
        "}"
        "QMenu::item:checked {"
        "  color: #60CDFF;"
        "  font-weight: bold;"
        "}"
        "QMenu::separator {"
        "  height: 1px;"
        "  background: rgba(255, 255, 255, 30);"
        "  margin: 4px 10px;"
        "}";

    inline const QString kSliderHorizontalStyle =
        "QSlider::groove:horizontal {"
        "  height: 4px;"
        "  background: rgba(255, 255, 255, 46);"
        "  border-radius: 2px;"
        "}"
        "QSlider::sub-page:horizontal {"
        "  background: #60CDFF;"
        "  border-radius: 2px;"
        "}"
        "QSlider::handle:horizontal {"
        "  background: #FFFFFF;"
        "  width: 12px;"
        "  height: 12px;"
        "  margin-top: -4px;"
        "  margin-bottom: -4px;"
        "  border-radius: 6px;"
        "}"
        "QSlider::handle:horizontal:hover {"
        "  background: #FFFFFF;"
        "  border: 2px solid #60CDFF;"
        "  width: 14px;"
        "  height: 14px;"
        "  margin-top: -5px;"
        "  margin-bottom: -5px;"
        "  border-radius: 7px;"
        "}";

    inline const QString kSliderVerticalStyle =
        "QSlider::groove:vertical {"
        "  width: 4px;"
        "  background: rgba(255, 255, 255, 46);"
        "  border-radius: 2px;"
        "}"
        "QSlider::add-page:vertical {"
        "  background: #60CDFF;"
        "  border-radius: 2px;"
        "}"
        "QSlider::handle:vertical {"
        "  background: #FFFFFF;"
        "  width: 12px;"
        "  height: 12px;"
        "  margin-left: -4px;"
        "  margin-right: -4px;"
        "  border-radius: 6px;"
        "}"
        "QSlider::handle:vertical:hover {"
        "  background: #FFFFFF;"
        "  border: 2px solid #60CDFF;"
        "  width: 14px;"
        "  height: 14px;"
        "  margin-left: -5px;"
        "  margin-right: -5px;"
        "  border-radius: 7px;"
        "}";
}
