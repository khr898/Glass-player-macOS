# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

All build commands are run from the `GlassPlayer/` directory:

```bash
# Install dependency (required once)
brew install mpv

# Standard build — compiles, bundles dylibs, signs, creates DMG, installs to /Applications
cd GlassPlayer && bash build.sh

# Fast development build — no install, no DMG, baseline optimization
cd GlassPlayer && BUILD_PROFILE=baseline NO_INSTALL=1 CREATE_DMG=0 bash build.sh

# CI-style build — no install, ad-hoc sign, create DMG
cd GlassPlayer && NO_INSTALL=1 SKIP_SIGN=1 CREATE_DMG=1 BUILD_PROFILE=optimized bash build.sh

# Run after building
open "/Applications/Glass Player.app"
open "/Applications/Glass Player.app" --args /path/to/video.mkv
```

### Build Options

| Variable | Default | Description |
|---|---|---|
| `BUILD_PROFILE` | `optimized` | `optimized` (LTO + aggressive opts) or `baseline` (fast compile) |
| `NO_INSTALL` | `0` | Set to `1` to skip copying to `/Applications` |
| `SKIP_SIGN` | `0` | Set to `1` to skip code signing |
| `CREATE_DMG` | `1` | Set to `0` to skip DMG creation |

Build output lands in `GlassPlayer/build/<profile>/`.

### Releasing

```bash
git tag v1.0.0
git push origin v1.0.0
```

This triggers the GitHub Actions workflow (`.github/workflows/release.yml`), which builds on a macOS 14 Apple Silicon runner and uploads a versioned DMG to GitHub Releases.

## Architecture

Glass Player is a native macOS video player built in Swift. There is **no Xcode project** — the build is driven entirely by `GlassPlayer/build.sh`, which compiles all Swift sources directly with `swiftc`.

### Rendering Pipeline

```
┌──────────────────┐    IOSurface     ┌───────────────────┐
│  mpv GPU renderer │──(shared UMA)──▸│  Metal 3 Pipeline  │──▸ CAMetalLayer → Screen
│  (offscreen CGL)  │                 │  (MTLRenderPSO)    │
└──────────────────┘                 └───────────────────┘
```

mpv's render API requires an OpenGL context (`MPV_RENDER_API_TYPE_OPENGL`). A **minimal offscreen CGL context** is created purely to satisfy this requirement — it is never used for display. mpv renders each frame into an **IOSurface-backed OpenGL FBO**. On Apple Silicon's Unified Memory Architecture, the same physical memory is accessed as a `MTLTexture` by the Metal pipeline — **no GPU-to-GPU copy occurs**. The Metal pipeline (`ViewLayer`) composites the texture to a `CAMetalLayer` drawable using a pre-compiled `MTLRenderPipelineState`.

### Source Files (`GlassPlayer/Sources/`)

| File | Responsibility |
|---|---|
| `main.swift` | Entry point |
| `AppDelegate.swift` | App lifecycle, menu bar, file opening, URL handling, Now Playing integration |
| `MPVController.swift` | libmpv wrapper — initialization, property observation, commands, shader presets, track parsing |
| `ViewLayer.swift` | `CAMetalLayer` subclass — IOSurface bridge, Metal 3 render pipeline, mpv render context setup |
| `VideoView.swift` | `NSView` hosting the `ViewLayer`; handles window resize and live-resize optimizations |
| `PlayerWindow.swift` | Player UI — controls overlay, format badges (codec/resolution/HDR/Atmos), keyboard shortcuts |
| `SettingsWindow.swift` | Preferences window — video, audio, subtitle, shader, cache, network settings (all persisted to `UserDefaults`) |
| `WelcomeWindow.swift` | Initial welcome/drop target screen |
| `RcloneBrowser.swift` | rclone remote file browser for cloud streaming |
| `UniversalSilicon.swift` | Hardware detection and QoS thread configuration |
| `Shaders.metal` | MSL 3.0 fullscreen quad vertex + fragment shaders (embedded as source for runtime fallback; pre-compiled to `default.metallib` by `build.sh`) |

### Key Design Patterns

**MPVController ↔ ViewLayer ↔ PlayerWindow**
`MPVController` is the mpv engine wrapper. `ViewLayer` owns the Metal + CGL rendering pipeline and holds a weak reference back to `MPVController`. `PlayerWindow` conforms to `MPVControllerDelegate` and receives property change callbacks (time-pos, pause, track changes, etc.) dispatched to the main thread.

**Settings persistence**
`SettingsWindow` writes to `UserDefaults`. On next launch, `MPVController.applyUserDefaultsToMPV()` reads those keys and applies them as mpv properties before playback starts.

**Shader presets**
Anime4K shader combinations are defined as named presets in `kShaderPresets` (in `MPVController.swift`). The bundled shaders live in `shaders/` (repo root) and are copied to `Contents/Resources/shaders/` by the build script. `MPVController` also searches `~/.config/mpv/shaders` and `~/Library/Application Support/mpv/shaders` as fallbacks.

**IOSurface lifecycle**
`ViewLayer.createIOSurface(width:height:)` creates both the GL texture/FBO (for mpv) and the `MTLTexture` (for Metal) from the same `IOSurface`. It is called on first render and on window resize. During live resize, IOSurface recreation is deferred until `liveResizeEnded()` fires to avoid per-frame GPU resource churn.

**Time-pos throttling**
The mpv event loop runs on a dedicated `Thread` (`com.glassplayer.mpv-event`). The `time-pos` property fires at video frame rate; `MPVController` throttles dispatches to the main thread to ≤30 Hz to avoid overwhelming the UI.

### Configuration

**`configs/mpv.conf`** — Default mpv configuration bundled into the app. The `[hdr-dv]` conditional profile activates automatically for PQ/HLG/BT.2020 content and applies HDR tone mapping. The `vo`, `force-window`, and `osc` options are enforced by `MPVController.initialize()` and cannot be overridden by this file.

**`GlassPlayer/BridgingHeader.h`** — Imports `<mpv/client.h>`, `<mpv/render_gl.h>`, and OpenGL headers for Swift/C interop.

**`GlassPlayer/GlassPlayer.entitlements`** — Code signing entitlements used during the build.

**`GlassPlayer/Info.plist`** — App metadata, bundle ID, file type associations (video formats), and URL scheme registrations.
