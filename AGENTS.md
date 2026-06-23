# Glass Player - AI Agent Guidelines

Glass Player is a high-performance, cross-platform media player with platform-specific implementations optimized for hardware acceleration.

## Quick Facts

| Aspect | Details |
|--------|---------|
| **Platforms** | macOS (Swift + Metal 3), Windows (C++ + Qt6 / WinUI) |
| **Rendering** | Zero-copy IOSurface pipeline (macOS), Direct3D 11 / Vulkan (Windows) |
| **Codec Backend** | libmpv |
| **Key Feature** | Real-time Anime4K upscaling, HDR, rclone cloud streaming |

---

## Build Commands

### macOS
```bash
cd macOS/GlassPlayer
./build.sh                           # Debug build (optimized=false)
BUILD_PROFILE=optimized ./build.sh   # Optimized release build
SKIP_SIGN=1 ./build.sh              # Skip code signing
CREATE_DMG=0 ./build.sh             # Skip DMG generation
```

**Output**: `macOS/GlassPlayer/build/optimized/Glass Player.app`

**Requirements**:
- Homebrew libmpv: `brew install mpv`
- Xcode Command Line Tools: `xcode-select --install`
- Target: arm64 macOS 14.0+ (Apple Silicon)

### Windows (Qt6)
```bash
cd windows
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
```

**Requirements**:
- Qt6 (automatic MOC/RCC/UIC processing)
- Visual Studio 2022 with C++20 support
- libmpv downloaded automatically from `vendor/mpv-dev/`

---

## Architecture Overview

### macOS (Swift + Metal 3)

**Key Files**:
- `AppDelegate.swift` — App lifecycle and file open handlers
- `PlayerWindow.swift` — Main UI window (3,546 LOC) containing playback logic
- `MPVController.swift` — libmpv bridge and hardware decoding
- `VideoView.swift` — Metal render surface
- `Shaders.metal` — Metal shader code compiled to `.metallib`

**Zero-Copy Pipeline**:
```
libmpv Decoder → IOSurface FBO → Metal 3 Texture → Display
        (shared unified memory, no GPU DMA overhead)
```

**Entry Point**: `AppDelegate.applicationDidFinishLaunching()`

### Windows (C++ + Qt6/WinUI)

**Key Files**:
- `main.cpp` — QApplication setup, IPC server
- `MainWindow.cpp/h` — Primary UI window with Qt signals/slots
- `RcloneBrowser.cpp/h` — Cloud integration UI
- `SettingsWindow.cpp/h` — Preferences dialog
- `WinOSIntegration.cpp/h` — Windows API integration

**Rendering**:
- Direct3D 11 swap chain for video output
- Qt6 event loop synced with libmpv playback thread

**Entry Point**: `main()` → QApplication → IPC server → MainWindow

---

## Development Conventions

### Code Style
- **Naming**: PascalCase classes, camelCase methods/variables
- **Indentation**: 4 spaces (Swift and C++)
- **Type Hints**: Explicit type annotations required
- **Guard Clauses**: Prefer early returns over nested conditionals

### Swift Organization (macOS)
- `// MARK: - SectionName` dividers for logical grouping
- Properties first, then methods
- Observers and subscripts inline near relevant properties

### C++ Organization (Windows)
- Member variables prefixed with `m_`
- Separate `.h` and `.cpp` files with clear interfaces
- Qt signals/slots organized by functionality

---

## Key Integration Points

### libmpv Integration

**macOS**:
```swift
// In MPVController.swift
// Establishes CGL context → IOSurface FBO → Metal texture binding
// Supports DXVA2, VDPAU hardware decode
```

**Windows**:
```cpp
// In MainWindow.cpp
// Direct3D 11 swap chain integration
// Event polling loop synced with Qt event loop
```

### Audio/Video Format Support

- **Audio Pass-Through**: Dolby Atmos, Dolby TrueHD, DTS-HD Master Audio
- **Video Codecs**: H.264, HEVC, AV1, VP9 (via libmpv decoders)
- **HDR**: Dolby Vision, HDR10, HLG with tone mapping

### Anime4K Shaders

- 37 GLSL shader files in `shaders/` directory
- Integrated in-app (hardcoded presets)
- Real-time GPU upscaling during playback
- Keyboard shortcut: `Cmd+K` (macOS) / `Ctrl+K` (Windows)

### rclone Cloud Integration

- Mounted via system-level integration in `RcloneBrowser` UI
- Low-latency streaming from cloud providers (Google Drive, S3, etc.)
- Configuration in `configs/mpv.conf`

---

## Common Tasks

### Adding Keyboard Shortcut
- **macOS**: Add case in `PlayerWindow.swift` keyDown handler
- **Windows**: Register in `MainWindow.cpp` event handling

### Adding Shader
- Place `.glsl` file in `shaders/` directory
- Update `mpv.conf` with shader-add entry
- Test via in-app preset cycling (`Cmd+K` / `Ctrl+K`)

### Debugging libmpv
- Enable libmpv logging via `mpv.conf`: `log-file=/tmp/mpv.log`
- Monitor frame timing in PlayerWindow info overlay (`I` key)

---

## Gotchas & Tips

1. **macOS JIT Entitlements**: Requires hardened runtime + JIT capability for libmpv
2. **Metal 3.0**: Minimum macOS 14.0 (Sonoma) requirement for Metal 3 features
3. **Windows CMake**: Architecture selection cached—clean `build/` folder if switching between x64/ARM64
4. **libmpv RPATH**: macOS binary uses `@loader_path/../Frameworks` for dylib resolution
5. **Qt6 Auto-Tooling**: MOC/RCC/UIC runs automatically—don't manually run these

---

## Resources

- [README.md](README.md) — Feature overview, keyboard shortcuts, system requirements
- `macOS/GlassPlayer/Sources/` — Swift implementation reference
- `windows/` — C++/Qt6 implementation reference
- `configs/mpv.conf` — libmpv configuration and shader options
- `shaders/` — Anime4K upscaling shader suite

---

## For AI Agents

When working on this codebase:

1. **Respect platform separation**: macOS (Swift/Metal) and Windows (C++/Qt6) are distinct implementations—changes often need parallel updates
2. **Test libmpv integration**: Verify hardware decoding and frame timing after modifications
3. **Follow build procedures**: Always test with `./build.sh` (macOS) or CMake (Windows) before suggesting changes
4. **Link to existing docs**: Refer users to [README.md](README.md) for feature documentation and keyboard shortcuts
5. **HDR/Color pipeline**: Complex topic—see libmpv documentation for tone mapping and color space handling
