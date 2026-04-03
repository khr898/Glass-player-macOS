# Glass Player

Glass Player is a native macOS video player focused on Apple Silicon and a full Metal rendering path. It uses libmpv for decoding and playback control, then presents frames through a Metal 3 pipeline with zero-copy IOSurface bridging.

The goal is straightforward: keep playback smooth, keep quality high, and avoid legacy display overhead.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-blue)
![Metal 3](https://img.shields.io/badge/Metal-3-orange)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

## Why Full Metal

- Display output is handled by Metal, not on-screen OpenGL.
- mpv frames are shared through IOSurface on Apple Silicon UMA, so there is no extra GPU copy.
- Anime4K upscaling runs as native Metal compute passes.

## Highlights

- Metal 3 presentation pipeline with Display P3 output
- Hardware decode via VideoToolbox (H.264, HEVC, VP9, AV1)
- Anime4K presets translated to Metal compute shaders
- HDR support (Dolby Vision, HDR10, HLG)
- Atmos and high-bitrate audio passthrough support
- Cloud browsing through rclone integration
- Track selection, subtitle controls, playback speed, resume support

## Requirements

- macOS 14.0 or newer
- Apple Silicon Mac (M1 and later)

## Install

Download the latest release from [Releases](../../releases), unzip, and move Glass Player.app to Applications.

If Gatekeeper blocks first launch on an unsigned build:
- Open System Settings → Privacy & Security → Open Anyway
- Or right-click the app in Finder and choose Open

## Build from Source

```bash
git clone https://github.com/khr898/Glass_player.git
cd Glass_player/GlassPlayer

# dependency
brew install mpv

# build and install to /Applications
bash build.sh
```

Useful build flags:

- BUILD_PROFILE=optimized|baseline
- NO_INSTALL=1 to skip installing
- SKIP_SIGN=1 for ad-hoc launch-stable local builds
- CREATE_DMG=0 to skip DMG generation

Example:

```bash
BUILD_PROFILE=baseline NO_INSTALL=1 SKIP_SIGN=1 CREATE_DMG=0 bash build.sh
```

## Quick Usage

```bash
open "/Applications/Glass Player.app"
open "/Applications/Glass Player.app" --args /path/to/video.mkv
```

## Keyboard Shortcuts

- Space: play or pause
- Left/Right: seek ±5s
- Up/Down: volume
- F: fullscreen
- M: mute
- Cmd+O: open file
- Cmd+, : settings

## Project Layout

- GlassPlayer/Sources: Swift app and Metal pipeline integration
- GlassPlayer/MetalShaders: translated Anime4K Metal shaders
- GlassPlayer/Tools: parity and soak tooling
- Scripts: shader export and maintenance scripts

## Release Workflow

Tagging a version triggers GitHub Actions release automation:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow is defined in [.github/workflows/release.yml](.github/workflows/release.yml).

## License

GPL-3.0. See [LICENSE](LICENSE).
