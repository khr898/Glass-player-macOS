# Glass Player

A lightweight, native macOS video player built on **Metal 3** and **libmpv**.  
Designed for Apple Silicon with zero-copy rendering, Anime4K shaders, and Dolby Vision / Atmos support.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-blue)
![Metal 3](https://img.shields.io/badge/Metal-3-orange)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

---

## Features

**Rendering**
- Native **Metal 3** display pipeline — no OpenGL on screen
- **IOSurface zero-copy** bridge (mpv GPU → Metal) on Apple Silicon UMA
- **Display P3** wide gamut color output
- Hardware-accelerated **VideoToolbox** decoding (H.264, HEVC, VP9, AV1)

**HDR & Audio**
- **Dolby Vision** and **HDR10/HLG** tone mapping with automatic SDR fallback
- **Dolby Atmos / TrueHD / DTS-HD** bitstream passthrough over HDMI/eARC
- Spatial Audio support for AirPods and HomePod (multichannel PCM)

**Player**
- Apple TV / Infuse-style **format badges** (codec, resolution, HDR, audio)
- Configurable **Anime4K** upscaling shaders (bundled)
- Built-in **rclone browser** for streaming from cloud storage
- Drag-and-drop, file associations, and CLI playback
- Picture-in-Picture style controls with auto-hide
- Subtitle and audio track selection
- Speed control, aspect ratio override, deband, and more
- macOS **Now Playing** integration (Control Center, AirPods)
- Settings window with per-option live apply
- Resume playback from last position

---

## Screenshots

<p align="center">
  <img src="screenshots/ss-1.jpg" width="800" alt="Screenshot 1">
</p>
<p align="center">
  <img src="screenshots/ss-2.jpg" width="800" alt="Screenshot 2">
</p>
<p align="center">
  <img src="screenshots/ss-3.jpg" width="800" alt="Screenshot 3">
</p>

---

## Requirements

| Requirement | Minimum |
|---|---|
| macOS | 14.0 Sonoma |
| Chip | Apple Silicon (M1 or later) |
| Homebrew | Required for building |

---

## Installation

### From Releases (recommended)

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG
3. Double-click **"Install Glass Player"** — this copies the app and clears the quarantine flag
4. Or drag to Applications manually, then run:
   ```bash
   xattr -cr "/Applications/Glass Player.app"
   ```

### Build from Source

```bash
# Install dependencies
# Option A: Install mpv WITHOUT vapoursynth (recommended, removes Python 3.14 dependency)
brew uninstall mpv 2>/dev/null || true
brew install ./Homebrew/mpv-no-vapoursynth.rb

# Option B: Install stock mpv (requires Python 3.14 for vapoursynth support)
# brew install mpv

# Clone
git clone https://github.com/khr898/Glass_player.git
cd Glass_player/GlassPlayer

# Build and install
bash build.sh
```

#### Why build mpv without vapoursynth?

The stock Homebrew mpv formula includes **vapoursynth** support, which requires Python 3.14. This creates a dependency chain that:
- Adds ~50MB of Python runtime overhead
- Requires users to install Python 3.14 if not already present
- Only benefits users who need vapoursynth video filters (niche feature)

**Glass Player recommends the vapoursynth-free build** because:
- Removes Python 3.14 dependency entirely
- Reduces app bundle size
- Faster installation (no Python download)
- No functional impact for playback + Anime4K upscaling

**Note:** If you need vapoursynth filters (VCC, VS scripts), use Option B and ensure Python 3.14 is installed.

The build script will:
- Compile Swift sources with Metal 3 shader precompilation
- Generate the app icon
- Bundle all dylibs into the `.app`
- Code sign (auto-detects your best identity, or ad-hoc)
- Create a DMG
- Install to `/Applications`

#### Build Options

| Variable | Default | Description |
|---|---|---|
| `BUILD_PROFILE` | `optimized` | `optimized` (LTO + aggressive opts) or `baseline` (fast compile) |
| `NO_INSTALL` | `0` | Set to `1` to skip copying to `/Applications` |
| `SKIP_SIGN` | `0` | Set to `1` to use local ad-hoc signing (skip identity/runtime signing path) |
| `CREATE_DMG` | `1` | Set to `0` to skip DMG creation |

```bash
# Example: fast debug build, no install
BUILD_PROFILE=baseline NO_INSTALL=1 bash build.sh
```

`SKIP_SIGN=1` still performs ad-hoc signing so local debug builds remain launchable after binary patching.

---

## Usage

```bash
# Open from Launchpad / Spotlight
# Or from terminal:
open "/Applications/Glass Player.app"

# Play a file directly:
open "/Applications/Glass Player.app" --args /path/to/video.mkv
```

- **Drag and drop** a video file onto the window or the app icon
- Use the **rclone browser** to stream from Google Drive, S3, etc.
- Open **Settings** (⌘,) to configure shaders, audio, debanding, and more

### Keyboard Shortcuts

| Key | Action |
|---|---|
| Space | Play / Pause |
| ← / → | Seek ±5s |
| ↑ / ↓ | Volume |
| F | Toggle fullscreen |
| M | Mute |
| [ / ] | Speed down / up |
| ⌘O | Open file |
| ⌘, | Settings |

---

## Architecture

```
┌──────────────────┐    IOSurface     ┌───────────────────┐
│  mpv GPU renderer │──(shared UMA)──▸│  Metal 3 Pipeline  │──▸ CAMetalLayer
│  (offscreen CGL)  │                 │  (MTLRenderPSO)    │      ▸ Screen
└──────────────────┘                 └───────────────────┘
```

Glass Player uses mpv's render API with an offscreen CGL context. mpv renders each frame to an **IOSurface-backed FBO**. On Apple Silicon's Unified Memory Architecture, the same physical memory is accessed by a Metal texture — **no GPU-to-GPU copy occurs**. The Metal pipeline composites the frame to a `CAMetalLayer` drawable using a precompiled `MTLRenderPipelineState`.

### Source Structure

```
GlassPlayer/
├── Sources/
│   ├── main.swift              # Entry point
│   ├── AppDelegate.swift       # App lifecycle, menus, file opening
│   ├── MPVController.swift     # libmpv wrapper, property observation
│   ├── ViewLayer.swift         # Metal 3 rendering layer (IOSurface bridge)
│   ├── VideoView.swift         # NSView hosting the Metal layer
│   ├── PlayerWindow.swift      # Player UI, controls, format badges
│   ├── SettingsWindow.swift    # Preferences (video, audio, shaders)
│   ├── WelcomeWindow.swift     # Welcome screen
│   ├── RcloneBrowser.swift     # rclone remote file browser
│   ├── UniversalSilicon.swift  # Hardware detection & QoS
│   ├── Shaders.metal           # Metal vertex/fragment shaders (display)
│   ├── Anime4KMetalPipeline.swift   # Anime4K pipeline orchestrator
│   └── Anime4KRuntimePipeline.swift # Metadata-driven Anime4K runtime pass executor
├── MetalShaders/
│   └── Anime4K_*.metal         # Anime4K compute shaders (Metal)
├── Tools/
│   └── preset_soak.zsh         # Preset stability soak test helper
├── BridgingHeader.h            # C/ObjC bridge for mpv + OpenGL
├── Info.plist                  # App metadata & file associations
└── build.sh                    # Build script (no Xcode required)
configs/
└── mpv.conf                    # Default mpv configuration
Scripts/
└── export_anime4kmetal_shaders.swift  # Export/translate helper using Anime4KMetal parser
```

---

## Anime4K Shaders

Glass Player bundles the full [Anime4K](https://github.com/bloc97/Anime4K) shader suite, translated to native **Metal compute shaders** for Apple Silicon GPU. Enable them in **Settings → Anime4K Enhancement**. Recommended presets:

| Quality | Shaders | Use Case |
|---|---|---|
| Fast | Restore CNN S + Upscale CNN x2 S | Smooth playback on all Macs |
| High | Restore CNN M + Upscale CNN x2 M | Good balance |
| Ultra | Restore CNN VL + Upscale CNN x2 VL | Best quality, M2 Pro+ |

### Repo Maintenance Utilities

The repository currently keeps a minimal maintenance script/tool set:

- `GlassPlayer/Tools/preset_soak.zsh`
  - Runs preset soak checks across Anime4K modes and writes summary logs.
- `Scripts/export_anime4kmetal_shaders.swift`
  - Exports required Anime4K GLSL shaders to Metal source using Anime4KMetal parsing logic.

---

## Releases

Releases are automated via GitHub Actions. To create a release:

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers the [release workflow](.github/workflows/release.yml) which builds the app, creates a DMG, and uploads it to GitHub Releases.

---

## Acknowledgments

- [mpv](https://mpv.io/) — the media player engine
- [FFmpeg](https://ffmpeg.org/) — audio/video decoding
- [Anime4K](https://github.com/bloc97/Anime4K) — real-time upscaling shaders

---

## License

This project is licensed under the [GPL-3.0 License](LICENSE) (due to FFmpeg/mpv dependency chain).  
Anime4K shaders are licensed under MIT by bloc97.
