# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Install dependencies
brew install mpv

# Build and install (from GlassPlayer directory)
bash build.sh

# Fast debug build (no install, no signing)
BUILD_PROFILE=baseline NO_INSTALL=1 SKIP_SIGN=1 bash build.sh

# Create release DMG
CREATE_DMG=1 NO_INSTALL=1 bash build.sh
```

The build script (`build.sh`) handles:
- Swift compilation with Metal 3 shader precompilation
- App icon generation
- dylib bundling into `.app`
- Code signing (auto-detects best identity or ad-hoc)
- DMG creation with install helper

## Run Commands

```bash
# Open from Applications
open "/Applications/Glass Player.app"

# Play a file
open "/Applications/Glass Player.app" --args /path/to/video.mp4

# Open with arguments from terminal
"/Applications/Glass Player.app/Contents/MacOS/GlassPlayer" /path/to/video
```

## Architecture Overview

Glass Player is a native macOS video player built on **Metal 3** and **libmpv** for Apple Silicon (M1/M2/M3/M4). It uses a zero-copy rendering pipeline:

```
┌──────────────────┐    IOSurface     ┌───────────────────┐
│  mpv GPU renderer │──(shared UMA)──▸│  Metal 3 Pipeline  │──▸ CAMetalLayer
│  (offscreen CGL)  │                 │  (MTLRenderPSO)    │      ▸ Screen
└──────────────────┘                 └───────────────────┘
```

**Key architectural points:**
- **mpv** handles decoding (VideoToolbox HW acceleration) and renders to an IOSurface-backed OpenGL FBO
- **IOSurface** provides zero-copy shared memory between mpv's GL renderer and Metal (Apple Silicon UMA)
- **Metal 3** composites the frame to `CAMetalLayer` using precompiled `MTLRenderPipelineState`
- **Display P3** wide gamut colorspace with HDR tone mapping support
- **Anime4K** upscaling via Metal compute shaders (optional pipeline)

## Source Structure

```
GlassPlayer/
├── Sources/
│   ├── main.swift                 # Entry point
│   ├── AppDelegate.swift          # App lifecycle, menus, file opening
│   ├── MPVController.swift        # libmpv wrapper, property observation, shader control
│   ├── ViewLayer.swift            # Metal 3 rendering (IOSurface bridge to mpv)
│   ├── VideoView.swift            # NSView hosting the Metal layer
│   ├── PlayerWindow.swift         # Player UI, controls, format badges, overlays
│   ├── SettingsWindow.swift       # Preferences (video, audio, shaders)
│   ├── WelcomeWindow.swift        # Welcome screen
│   ├── RcloneBrowser.swift        # rclone remote file browser
│   ├── Anime4KMetalPipeline.swift # Metal compute pipeline for Anime4K shaders
│   ├── UniversalSilicon.swift     # Hardware detection & QoS
│   └── Shaders.metal              # Metal vertex/fragment shaders (display)
├── MetalShaders/                  # Anime4K .metal compute shaders
├── BridgingHeader.h               # C/ObjC bridge (mpv, OpenGL, IOSurface)
├── Info.plist                     # App metadata & file associations
└── build.sh                       # Build script (no Xcode required)
```

## Key Dependencies

| Dependency | Purpose |
|------------|---------|
| **libmpv** | Media engine (decoding, playback control) |
| **Metal 3** | Display rendering pipeline |
| **IOSurface** | Zero-copy GL↔Metal bridge (UMA) |
| **OpenGL/CGL** | Offscreen context for mpv render API (minimal, not for display) |
| **Accelerate** | SIMD-optimized math (clamping, DSP) |
| **IOKit** | Power source monitoring, display sleep prevention |

## Common Tasks

### Adding a new video property

1. Add property observation in `MPVController.initialize()` (line ~175-189)
2. Parse in `getVideoInfo()` or `getFormatBadges()`
3. Display in `PlayerWindow.showVideoInfo()`

### Adding a new Anime4K preset

1. Add `.metal` shader file to `MetalShaders/`
2. Add preset definition in `Anime4KMetalPipeline.presetDefinitions`
3. Preset name appears automatically in Settings UI

### Modifying playback behavior

- Keyboard shortcuts: `AppDelegate.setupMenu()` + action methods
- Mouse gestures: `PlayerWindow` event handlers
- mpv property changes: `MPVController.setPropertyString()` or `command()`

### Settings persistence

Settings are stored in `UserDefaults` and applied to mpv via `applyUserDefaultsToMPV()` in `MPVController`. Each setting maps to an mpv property.

## Release Process

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers the GitHub Actions workflow (`.github/workflows/release.yml`) which builds the app, creates a DMG, and uploads to GitHub Releases.

## Testing Notes

- No formal unit tests — manual testing via file playback
- Key test scenarios: HDR/Dolby Vision, Anime4K shaders, spatial audio, rclone streaming
- Build verifies with `otool -L` and codesign verification
