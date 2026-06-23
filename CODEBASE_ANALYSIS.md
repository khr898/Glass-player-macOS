# Glass Player: Comprehensive Codebase Analysis

**Version**: 2.0.0 | **Last Updated**: 2026-06-23

A detailed architectural and developmental guide for the Glass Player codebase, designed to help AI agents and developers quickly become productive.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Build System & Commands](#build-system--commands)
3. [Project Structure](#project-structure)
4. [Architecture & Design Patterns](#architecture--design-patterns)
5. [Development Conventions](#development-conventions)
6. [Environment Setup & Gotchas](#environment-setup--gotchas)
7. [Platform Integration with libmpv](#platform-integration-with-libmpv)
8. [Key Entry Points](#key-entry-points)

---

## 1. Project Overview

### Core Identity
- **Multi-platform media player** optimized for high-performance, hardware-accelerated video playback
- **macOS**: Swift + Metal 3 (Apple Silicon M1-M5)
- **Windows**: C++ + Qt6 (x64 & ARM64)
- **Backend**: libmpv with GPU acceleration, HDR support, Anime4K shaders, rclone cloud integration

### Key Features
- **Zero-Copy Pipeline** (macOS): IOSurface-backed FBO → Metal texture (unified memory)
- **Hardware Decoding**: VideoToolbox (macOS), DXVA2/Direct3D 11 (Windows)
- **HDR Support**: Dolby Vision, HDR10, HLG with tone mapping
- **Real-Time Upscaling**: 10+ Anime4K shader presets
- **Cloud Integration**: rclone mounts for remote media streaming
- **High-Fidelity Audio**: Bitstream pass-through (Dolby Atmos, DTS-HD Master Audio)

### System Requirements
| Platform | OS | Hardware |
|----------|-----|----------|
| macOS | 14.0+ (Sonoma) | Apple Silicon (M1/M2/M3/M4/M5) |
| Windows | 10/11 (64-bit, ARM64) | DirectX 11+ or Vulkan GPU |

---

## 2. Build System & Commands

### 2.1 macOS Build

**Prerequisites:**
- Xcode Command Line Tools
- Homebrew with libmpv: `brew install mpv`
- Swift 5.9+ (included with Xcode)

**Build Process:**
```bash
cd macOS/GlassPlayer
./build.sh
```

**Build Script Internals** (`build.sh`):
- **Environment**: Bash (zsh-compatible)
- **Profile**: `BUILD_PROFILE={optimized|debug}` (default: optimized)
- **Compilation**: Direct swiftc invocation with:
  - `-O -whole-module-optimization -lto=llvm-thin` (optimized profile)
  - `-import-objc-header BridgingHeader.h` for C/Objective-C interop
  - Frameworks: `Metal`, `IOSurface`, `QuartzCore`, `CoreVideo`, `IOKit`, `AVFoundation`
  - Linking: `-lmpv` from homebrew (`/opt/homebrew/lib`)
- **Output**: Standalone `.app` bundle with:
  - Metal shader compilation (`Shaders.metal` → `default.metallib`)
  - dylib bundling and rpath resolution
  - DMG generation (optional)

**Build Configuration Files:**
- `UniversalSilicon.xcconfig`: Architecture flags, optimization settings
- `GlassPlayer.entitlements`: JIT, unsigned executable memory, library validation bypass
- `Info.plist`: Bundle metadata, minimum OS (14.0), file type associations

**Important Build Flags:**
```swift
COMMON_SWIFTC_FLAGS=(
    -import-objc-header "$PROJECT_DIR/BridgingHeader.h"
    -I /opt/homebrew/include
    -L /opt/homebrew/lib
    -lmpv
    -framework Cocoa
    -framework Metal
    -framework OpenGL  # minimal: CGL offscreen for mpv interop
    -framework IOSurface
    -framework IOKit
    -target arm64-apple-macos14.0
)
```

---

### 2.2 Windows Build

**Prerequisites:**
- Visual Studio 2022 (C++ workload)
- CMake 3.20+
- Qt6 development libraries
- MSVC ARM64 toolchain (for ARM64 builds)

**CMake Configuration & Build:**

#### x64 Build
```powershell
cd <repo-root>
cmake -S windows -B build-win-x64 -G "Visual Studio 17 2022" -A x64
cmake --build build-win-x64 --config Release
```

#### ARM64 Build
```powershell
cmake -S windows -B build-win-ARM64 -G "Visual Studio 17 2022" -A ARM64
cmake --build build-win-ARM64 --config Release
```

**CMakeLists.txt Structure** (`windows/CMakeLists.txt`):
- **C++ Standard**: C++20
- **Qt6 Components**: `Core`, `Gui`, `Widgets`, `OpenGLWidgets`, `Network`, `Svg`
- **Automation**: `CMAKE_AUTOMOC`, `CMAKE_AUTORCC`, `CMAKE_AUTOUIC`
- **libmpv Resolution**:
  - Primary: `pkg-config` (if available)
  - Fallback: Vendor path `vendor/mpv-dev/{x64,arm64}/`
  - Headers: `mpv/client.h`, `mpv/render.h`
  - Libraries: `libmpv.lib`, `libmpv.dll.a`
  - Runtime: `libmpv-2.dll` auto-copied to build dir
- **Linking**: `Qt6::*`, `d3d11.lib`, `dxgi.lib`, `dxva2.lib`, `dwmapi.lib`, `wbemuuid.lib`

**Windows Build Output:**
- `build-win-x64/Release/GlassPlayer.exe`
- `build-win-x64/Release/libmpv-2.dll` (auto-copied)

**Automatic libmpv Download:**
- Script: `windows/download_mpv.py`
- Source: SourceForge (RSS feed for latest builds)
- Fallback: Hardcoded URL pointing to specific dated builds
- Execution: Pre-CMake step or manual: `python download_mpv.py --arch x64`

---

## 3. Project Structure

### 3.1 Directory Layout

```
Glass-player/
├── README.md                    # High-level overview & user guide
├── LICENSE                      # GPL-3.0 (libmpv, FFmpeg dependencies)
├── .github/workflows/
│   └── release.yml              # CI/CD: macOS & Windows release builds
│
├── macOS/                       # Apple Silicon Swift implementation
│   └── GlassPlayer/
│       ├── build.sh             # Main build script
│       ├── BridgingHeader.h     # Swift-C/Objective-C bridge (mpv, IOSurface)
│       ├── Info.plist           # App metadata, file associations
│       ├── GlassPlayer.entitlements  # Security: JIT, lib validation
│       ├── UniversalSilicon.xcconfig # Build config
│       ├── Sources/             # All Swift source files (8,918 LOC total)
│       │   ├── main.swift
│       │   ├── AppDelegate.swift         (867 LOC) – app lifecycle, menu bar
│       │   ├── PlayerWindow.swift        (3546 LOC) – main UI, controls
│       │   ├── MPVController.swift       (1090 LOC) – libmpv interface
│       │   ├── VideoView.swift           (98 LOC) – NSView hosting Metal layer
│       │   ├── ViewLayer.swift           (789 LOC) – CAMetalLayer, rendering
│       │   ├── SettingsWindow.swift      (1172 LOC) – UI settings dialog
│       │   ├── RcloneBrowser.swift       (724 LOC) – cloud file browser
│       │   ├── WelcomeWindow.swift       (319 LOC) – initial UI
│       │   ├── UniversalSilicon.swift    (306 LOC) – QoS, Accelerate, SIMD
│       │   └── Shaders.metal             (MSL 3.0 rendering pipeline)
│       └── build/               # Output directory
│
├── windows/                     # Windows Qt6 C++ implementation
│   ├── CMakeLists.txt           # Build configuration
│   ├── main.cpp                 # Entry point, Qt app setup, IPC server
│   ├── MainWindow.{h,cpp}       # Main UI window
│   ├── SettingsWindow.{h,cpp}   # Settings dialog
│   ├── WelcomeWindow.{h,cpp}    # Welcome/empty state
│   ├── RcloneBrowser.{h,cpp}    # Cloud browser
│   ├── WinOSIntegration.{h,cpp} # Windows-specific features
│   ├── app.rc                   # Resource script (icon, version)
│   ├── download_mpv.py          # Dependency downloader
│   ├── installer.iss            # Inno Setup installer config
│   ├── icons/                   # SVG and other icon assets
│   ├── build/                   # CMake build artifacts
│   └── GlassPlayerWindows.sln   # Visual Studio solution
│
├── windows-winui/               # Windows WinUI 3 / XAML implementation (in progress)
│   ├── App.xaml, App.xaml.cpp   # WinUI app entry
│   ├── MainWindow.xaml          # Main UI (XAML markup)
│   ├── MainWindow.xaml.cpp      # UI code-behind
│   ├── RenderHost.cpp           # Custom render host for libmpv
│   ├── SettingsWindow.xaml      # Settings UI
│   ├── WelcomeWindow.xaml       # Welcome UI
│   ├── Directory.Build.props    # MSBuild properties
│   ├── Directory.Build.targets  # MSBuild targets
│   └── Win32/                   # Win32 interop headers
│
├── vendor/                      # External dependencies
│   ├── mpv-dev/
│   │   ├── x64/                 # libmpv headers & libs for x86_64
│   │   │   ├── include/mpv/      # mpv C API
│   │   │   ├── libmpv.lib
│   │   │   └── libmpv-2.dll
│   │   └── arm64/               # libmpv for ARM64
│   └── angle/                   # ANGLE (OpenGL ES on D3D11)
│       └── x64/include/         # GLES3 headers
│
├── configs/
│   ├── mpv.conf                 # Global libmpv configuration
│   └── watch_later/             # Resume playback state storage
│
├── shaders/                     # Anime4K GPU shaders (MIT license)
│   ├── Anime4K_Upscale_CNN_x2_*.glsl
│   ├── Anime4K_Restore_CNN_*.glsl
│   ├── Anime4K_Denoise_*.glsl
│   └── ... (37 shader files)
│
├── screenshots/                 # UI screenshots for docs
└── build/                       # Release build output
    └── x64/Release/             # Compiled executables
```

### 3.2 macOS Source File Details

| File | LOC | Purpose |
|------|-----|---------|
| `main.swift` | 7 | Entry point, app initialization |
| `AppDelegate.swift` | 867 | Lifecycle, menu bar, file opening, window management |
| `PlayerWindow.swift` | 3546 | **LARGEST**: Main UI, keyboard shortcuts, controls |
| `MPVController.swift` | 1090 | libmpv C API wrapper, playback control |
| `ViewLayer.swift` | 789 | Metal 3 rendering, IOSurface bridge |
| `SettingsWindow.swift` | 1172 | Settings UI, preferences persistence |
| `RcloneBrowser.swift` | 724 | Cloud file browser, remote streaming |
| `UniversalSilicon.swift` | 306 | QoS, Accelerate, memory pressure monitoring |
| `VideoView.swift` | 98 | NSView wrapper for Metal layer |
| `WelcomeWindow.swift` | 319 | Initial UI, drag-and-drop support |
| `Shaders.metal` | ~150 | MSL 3.0 display pipeline |

### 3.3 Windows Source File Details

| File | Purpose |
|------|---------|
| `main.cpp` | Qt app initialization, IPC server for single-instance control |
| `MainWindow.{h,cpp}` | Primary Qt UI, timeline, controls, menus |
| `SettingsWindow.{h,cpp}` | Settings dialog |
| `WelcomeWindow.{h,cpp}` | Welcome/empty state UI |
| `RcloneBrowser.{h,cpp}` | Cloud browser interface |
| `WinOSIntegration.{h,cpp}` | Windows-specific features (desktop integration, etc.) |

---

## 4. Architecture & Design Patterns

### 4.1 macOS Architecture: Zero-Copy Metal 3 Pipeline

```
┌──────────────────────────────────────────────────────────┐
│ Architectural Flow (Apple Silicon UMA)                   │
└──────────────────────────────────────────────────────────┘

[libmpv Decoder/GPU Backend]
        │ (offscreen CGL context)
        │ (OpenGL FBO target)
        ▼
    [IOSurface Shared Buffer]
        │ (unified memory address)
        │ (MTLResourceStorageModeShared)
        ▼
 [Metal 3 Render Pipeline]
        │ (statically compiled MTLRenderPipelineState)
        │ (no per-frame state changes)
        ▼
  [CAMetalLayer]
        │ (High-DPI contentsScale)
        │ (EDR/HDR enabled)
        ▼
   [Display Output]
```

**Key Architectural Decisions:**

1. **Minimal OpenGL Dependency**:
   - libmpv's render API **requires** an OpenGL context type (`MPV_RENDER_API_TYPE_OPENGL`)
   - Offscreen CGL context used **only** for mpv interop, NOT for display
   - No OpenGL calls for screen rendering—all display is Metal 3

2. **Zero-Copy via IOSurface**:
   - mpv renders to OpenGL FBO backed by IOSurface
   - Metal immediately binds IOSurface as texture (MTLTextureDescriptor)
   - Physical memory shared: no GPU-to-GPU DMA required
   - Only true on Apple Silicon (ARM64); Intel Macs have limited UMA

3. **Static Pipeline State**:
   - `MTLRenderPipelineState` compiled once at init, never recreated
   - Replaces OpenGL state machine calls (glBlendFunc, glEnable, etc.)
   - Dramatically reduces per-frame CPU overhead

4. **QoS-Based Dispatch**:
   - Heavy work (video info, thumbnail generation, shader compilation) → P-cores (`.userInitiated`)
   - Maintenance (cache cleanup, logging) → E-cores (`.background`)
   - Automatic on M-series; no chip-specific code

### 4.2 Windows Architecture: Qt6 Thread-Based Rendering

```
┌──────────────────────────────────────────────────────────┐
│ Windows Architecture (Qt6 + libmpv)                      │
└──────────────────────────────────────────────────────────┘

[Qt6 Main Thread]
    ├── Event loop
    ├── UI updates
    └── IPC server (single-instance control)
        │
        ▼
[libmpv Playback Core]
    ├── Video decoding (hardware: DXVA2)
    ├── Frame rendering (Direct3D 11 or Vulkan)
    └── Audio processing
        │
        ▼
[Qt6 OpenGL/D3D Viewport]
    ├── Display integration
    └── Swap chain presentation
```

**Architecture Characteristics:**

1. **Single-Instance IPC**:
   - Primary instance listens on named pipe (`QLocalServer`)
   - Secondary instances send command string, exit
   - Allows `open -a GlassPlayer <file>` to work correctly

2. **Hardware Decoding**:
   - Windows: DXVA2 (Direct3D Video Acceleration 2)
   - Fallback chain: H.264 DXVA → software decode

3. **Rendering Path**:
   - Qt6 abstraction over Direct3D 11 or Vulkan
   - Swap interval set to 1 (V-Sync) in `QSurfaceFormat`
   - High-DPI scaling via `Qt::HighDpiScaleFactorRoundingPolicy::PassThrough`

### 4.3 Shared Architecture Patterns

#### 1. **Delegate Protocol (macOS)**
```swift
protocol MPVControllerDelegate: AnyObject {
    func mpvPropertyChanged(_ name: String, value: Any?)
    func mpvFileLoaded()
    func mpvPlaybackEnded()
    func mpvTracksChanged(_ tracks: [TrackInfo])
}
```
- `PlayerWindow` conforms to delegate
- Decouples playback logic from UI updates

#### 2. **Observable Properties**
- macOS: `@Published` (Combine) in controller classes
- Windows: Qt's `Q_PROPERTY` + signals/slots
- Enables reactive UI updates

#### 3. **Anime4K Shader Presets**
Hardcoded shader chains by GPU class:
```swift
let kShaderPresets: [String: [String]] = [
    "Mode A (HQ)": ["Anime4K_Clamp_Highlights.glsl", ...],  // M1 Pro/Max+
    "Mode B (Fast)": [...],  // M1 base
]
```

#### 4. **Video Info Snapshot**
```swift
struct VideoInfo {
    var filename, codec, width, height, duration: ...
    var isDolbyVision, isHDR10, isHLG: Bool
    var audioChannelLayout, audioBitrate: ...
}
```
- Populated from mpv property callbacks
- Displayed in video info overlay (press 'i')

---

## 5. Development Conventions

### 5.1 Naming Conventions

#### macOS (Swift)
- **Classes**: PascalCase (e.g., `PlayerWindow`, `MPVController`)
- **Structs**: PascalCase (e.g., `TrackInfo`, `VideoInfo`)
- **Protocols**: PascalCase, often with `-Delegate` suffix (e.g., `MPVControllerDelegate`)
- **Properties**: camelCase (e.g., `playerWindow`, `currentMediaSource`)
- **Methods**: camelCase, verb-first (e.g., `openFile(_:)`, `setPreview(_:)`)
- **Private members**: prefix with underscore (e.g., `_renderState`)
- **Constants**: UPPER_SNAKE_CASE for global constants, PascalCase for enums

#### Windows (C++)
- **Classes**: PascalCase (e.g., `MainWindow`, `ClickableSlider`)
- **Member variables**: `m_camelCase` (Qt convention, e.g., `m_imgLabel`, `m_tmpPath`)
- **Methods**: camelCase (e.g., `shutdown()`, `loadSource()`)
- **Qt signals**: `&Class::signalName` (Qt convention)
- **Qt slots**: Private/public methods prefixed with `on` or verb (e.g., `onButtonClicked()`)

### 5.2 Code Organization

#### macOS
- **File per class**: One major class per `.swift` file
- **Nested types**: Small helpers (structs, enums) defined within the main class file
- **MARK comments**: Heavy use of `// MARK: - Section Name` for code organization
- **Extensions**: Used for protocol conformance
- **Access modifiers**: Explicit (`public`, `private`, `fileprivate`)

#### Windows
- **Header-Implementation split**: `.h` and `.cpp` for each component
- **Qt idioms**: `Q_OBJECT`, `Q_PROPERTY`, `signals:`, `public slots:`
- **Includes**: Qt headers first, then system, then project headers
- **Memory management**: `new`/`delete`, but Qt handles cleanup via parent-child relationships

### 5.3 File Organization

#### macOS `Sources/` Directory
- One class per file (mostly)
- Alphabetical order within file (MARK sections)
- Related helper structs/protocols in same file as primary class

#### Windows Directory
- Logical grouping: `MainWindow.{h,cpp}`, `SettingsWindow.{h,cpp}`
- `icons/` subdirectory for assets
- `build/` auto-generated by CMake

### 5.4 Code Style

#### macOS Swift
- **Indentation**: 4 spaces
- **Line length**: Soft limit ~100 chars (MARK sections often exceed)
- **Brace style**: Allman (opening brace on same line)
- **Guard clauses**: Heavy use of `guard let` and early returns
- **Type annotations**: Explicit where clarity aids readability

#### Windows C++
- **Indentation**: 4 spaces (Qt convention)
- **Line length**: ~100 chars
- **Brace style**: Opening brace on same line (C++ convention)
- **Auto**: Heavy use for complex types (Qt containers)
- **Lambdas**: Used for callbacks, especially with Qt signals

### 5.5 Documentation Style

#### macOS
- **Docstrings**: Comments above methods (not formal Swift doc syntax)
- **Inline comments**: Explain "why" not "what"
- **Section headers**: `// ─── Section Name ───`

Example:
```swift
// ─── Bottom controls bar ──
private let controlsContainer = createLiquidGlassView()

// Timeline row
private let timelineSlider = GlassSlider()
```

#### Windows
- **Header comments**: Minimal; code is self-documenting via Qt idioms
- **Implementation comments**: Explain complex logic
- **Signal/slot connections**: Comments noting why they're connected

---

## 6. Environment Setup & Gotchas

### 6.1 macOS Setup

#### Prerequisites
1. **Xcode Command Line Tools**:
   ```bash
   xcode-select --install
   ```

2. **Homebrew libmpv**:
   ```bash
   brew install mpv
   ```
   - Installs to `/opt/homebrew/lib/libmpv.dylib` and `/opt/homebrew/include/mpv/`
   - Header location: `$HOMEBREW_PREFIX/include/mpv`

3. **Swift Version**: 5.9+ (bundled with Xcode 15+)

#### Build Gotchas

1. **rpath Resolution**:
   - `build.sh` resolves dynamic library paths recursively
   - If `libmpv` or its dependencies (ffmpeg, etc.) have broken rpaths, linking fails
   - Solution: Manually fix with `install_name_tool -change OLD NEW libmpv.dylib`

2. **Icon Generation**:
   - `build.sh` generates `AppIcon.icns` from scratch
   - Requires `iconutil` (part of Xcode)
   - SVG-to-PNG step uses a compiled Swift utility script

3. **Metal Shader Compilation**:
   - `Shaders.metal` compiled via `xcrun metal -c ...`
   - Requires Metal 3.0 support (macOS 14.0+)
   - Compilation errors appear during build, not at compile time

4. **JIT Entitlements**:
   - `GlassPlayer.entitlements` enables:
     - `com.apple.security.cs.allow-jit` (LuaJIT for mpv scripts)
     - `com.apple.security.cs.allow-unsigned-executable-memory`
     - `com.apple.security.cs.disable-library-validation`
   - Without these, mpv's built-in Lua scripts (`stats`, `console`) fail

5. **DMG Creation**:
   - `build.sh` optional DMG creation (set `CREATE_DMG=0` to skip)
   - Requires Finder volume mounting capabilities

#### Development Tips
- **Incremental builds**: Deleting `build/$BUILD_PROFILE` forces full rebuild
- **No Xcode project**: Build via shell script only; no `.xcodeproj` to maintain
- **Manual testing**: Run `./build.sh` and then `./$BUILD_PROFILE/Glass\ Player.app/Contents/MacOS/Glass\ Player`

---

### 6.2 Windows Setup

#### Prerequisites
1. **Visual Studio 2022**:
   - Workload: "Desktop development with C++"
   - Optional: C++ ARM64 build tools (for ARM64 builds)

2. **CMake 3.20+**:
   ```powershell
   cmake --version
   ```

3. **Qt6 Development Libraries**:
   - Option A (Online Installer): Download from qt.io
   - Option B (vcpkg): `vcpkg install qt6:x64-windows`
   - Components needed: `Core`, `Gui`, `Widgets`, `OpenGLWidgets`, `Network`, `Svg`

4. **Python 3.7+** (for `download_mpv.py`):
   - Used by build script to auto-download libmpv binaries

5. **7-Zip** (for `download_mpv.py`):
   - Extracts downloaded `.7z` files
   - Install to `C:\Program Files\7-Zip\` or use `7z` from PATH

#### CMake Configuration Gotchas

1. **Qt6 Auto-tooling**:
   - `CMAKE_AUTOMOC`, `CMAKE_AUTORCC`, `CMAKE_AUTOUIC` are **enabled**
   - MOC (Meta-Object Compiler) runs automatically; do not set up manually
   - `.ui` files automatically become header files

2. **libmpv Download**:
   - First run: CMake may not find libmpv
   - Solution: `python windows/download_mpv.py --arch x64` before CMake
   - Then re-run CMake to pick up vendor directory

3. **Architecture Mismatch**:
   - `-A x64` and `-A ARM64` are mutually exclusive
   - Create separate build directories: `build-win-x64`, `build-win-ARM64`
   - CMakeCache.txt caches architecture; cannot reuse directories

4. **DLL in Build Directory**:
   - CMakeLists.txt auto-copies `libmpv-2.dll` to build output
   - Necessary for running tests from IDE without installation

#### Build Performance
- First build: ~2-3 minutes (Qt MOC, compiler cache)
- Incremental: ~30 seconds (if only `.cpp` changes)
- Full rebuild: Clean `build-win-x64/` and reconfigure

#### Windows-Specific Compilation Notes
- **MSVC C++20**: Some features (modules, concepts) may behave differently than GCC/Clang
- **D3D11 & DXGI**: Windows SDK auto-linked; no separate installation needed
- **Qt Creator vs Visual Studio**: Both work; solution file generated by CMake

---

### 6.3 CI/CD Setup

**GitHub Actions Workflow** (`.github/workflows/release.yml`):

1. **Version Detection**:
   - Reads git tag (e.g., `v2.2.0`)
   - Falls back to timestamp if no tag

2. **Matrix Builds**:
   - **macOS arm64**: `macos-26` runner
   - **Windows x64**: `windows-latest` runner
   - **Windows ARM64**: `windows-latest` runner (cross-compile via MSVC)

3. **Build Steps**:
   - Checkout code
   - Set up environment (Qt, libmpv, etc.)
   - Compile
   - Package (DMG on macOS, NSIS installer on Windows)
   - Create GitHub Release with artifacts

4. **Automatic libmpv Download**:
   - CI triggers `download_mpv.py` as pre-build step
   - Falls back to hardcoded SourceForge URL if RSS fetch fails

---

## 7. Platform Integration with libmpv

### 7.1 libmpv C API Overview

**Key Headers** (vendored in `vendor/mpv-dev/`):
- `mpv/client.h`: Core playback API
- `mpv/render.h`: Render context API
- `mpv/render_gl.h`: OpenGL render backend params

**Core Data Types**:
```c
typedef struct mpv_handle mpv_handle;           // Playback instance
typedef struct mpv_render_context mpv_render_context;  // Render context
typedef void (*mpv_update_cb)(void *ctx);      // Callback for frame updates
```

### 7.2 macOS Integration: IOSurface Bridge

#### Initialization Flow
1. **Create CGL context** (for mpv compatibility):
   ```swift
   let cglPix = CGLPixelFormatObj()
   CGLChoosePixelFormat(&attrs, &cglPix, &numPix)
   CGLCreateContext(cglPix, nil, &cglCtx)
   ```

2. **Create IOSurface-backed FBO**:
   ```c
   IOSurface surface = IOSurfaceCreate(props);
   glGenFramebuffers(1, &fbo);
   CGLTexImageIOSurface2D(cglCtx, GL_TEXTURE_2D, ..., surface, 0);
   ```

3. **Initialize mpv render context** with OpenGL:
   ```c
   mpv_render_param params[] = {
       {MPV_RENDER_PARAM_API_TYPE, "opengl"},
       {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init_params},
       {0}
   };
   mpv_render_context_create(&render_ctx, mpv_handle, params);
   ```

4. **Bind IOSurface to Metal texture**:
   ```swift
   let texDesc = MTLTextureDescriptor.texture2DDescriptor(...)
   texDesc.resourceOptions = .storageModeShared
   let metalTexture = mtlDevice.makeTexture(descriptor: texDesc, iosurface: surface, plane: 0)
   ```

#### Per-Frame Rendering
1. **Check for frame update**:
   - mpv triggers callback when new frame available
   - Callback enqueues render on Metal command queue

2. **Render via mpv**:
   ```c
   mpv_render_param params[] = {
       {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
       {MPV_RENDER_PARAM_FLIP_Y, &flip},
       {0}
   };
   mpv_render_context_render(render_ctx, params);
   ```

3. **Metal display**:
   ```swift
   let cmdBuffer = commandQueue.makeCommandBuffer()
   let encoder = cmdBuffer.makeRenderCommandEncoder(...)
   encoder.setRenderPipelineState(pipelineState)
   encoder.setVertexBytes(&matrix, length: ..., index: 0)
   encoder.drawPrimitives(.triangleStrip, vertexStart: 0, vertexCount: 4)
   ```

### 7.3 Windows Integration: Direct3D 11 / Qt Backend

#### Initialization
1. **Create libmpv instance**:
   ```cpp
   mpv_handle *mpv = mpv_create();
   mpv_set_option_string(mpv, "video-output-levels", "full");
   mpv_initialize(mpv);
   ```

2. **Set up render context** (Qt/Direct3D abstraction):
   - Qt6 manages D3D11 device and swap chain internally
   - libmpv configured to render directly to swap chain

3. **Register event observer**:
   ```cpp
   mpv_observe_property(mpv, 0, "track-list", MPV_FORMAT_NODE);
   mpv_observe_property(mpv, 0, "playback-time", MPV_FORMAT_DOUBLE);
   ```

#### Per-Frame Updates
1. **Poll events**:
   ```cpp
   mpv_event *event = mpv_wait_event(mpv, timeout);
   if (event->event_id == MPV_EVENT_PROPERTY_CHANGE) {
       // Update UI based on property change
   }
   ```

2. **Render**:
   - Qt handles presentation via swap chain
   - libmpv output appears directly in Qt viewport

### 7.4 HDR/Dolby Vision Support

#### macOS
- **Hardware decoding**: `hwdec=videotoolbox` (in `configs/mpv.conf`)
- **HDR signaling**: `target-colorspace-hint=yes` (conditionally enabled for HDR content)
- **Tone mapping**: `tone-mapping=spline`
- **Peak detection**: `hdr-compute-peak=yes`
- **Display support**: Requires macOS 14.0+ with EDR-capable display

#### Windows
- **Hardware decoding**: DXVA2 (built-in to Direct3D 11)
- **HDR support**: Direct3D 11 HDR swap chains (Windows 10+)
- **No explicit HDR config needed**: libmpv auto-detects and configures

### 7.5 Audio Configuration (libmpv)

**Key Settings** (`configs/mpv.conf`):
```ini
ao=avfoundation              # macOS audio output
audio-channels=auto          # Preserve source channel layout
audio-spdif=                 # Bitstream pass-through (off by default)
volume-max=200               # Allow 2x amplification
```

**Special Cases**:
- **Dolby Atmos**: Requires multichannel PCM; macOS renders spatial audio
- **Bitstream pass-through**: Requires `audio-spdif=ac3,eac3,truehd,dts,dtshd`

---

## 8. Key Entry Points

### 8.1 macOS Entry Points

#### Application Launch
1. **`main.swift`** (7 LOC):
   ```swift
   let app = NSApplication.shared
   let delegate = AppDelegate()
   app.delegate = delegate
   app.run()
   ```

2. **`AppDelegate.applicationDidFinishLaunching(_:)`**:
   - Disables automatic window restoration
   - Logs hardware profile
   - Sets up menu bar
   - Defers welcome window display to allow file associations to fire

3. **File Open Paths**:
   - Command-line argument: `app.arguments[1]` → `openFile(_:)`
   - File association (Finder): `application(_:open:)` → `openFile(_:)`
   - Drag-and-drop: `VideoView.performDragOperation(_:)` → `AppDelegate.openFile(_:)`

#### Player Window Creation
1. **`AppDelegate.openFile(_ path: String)`**:
   - Creates new `PlayerWindow` if none exists or current one has content
   - Enforces max 10 windows

2. **`PlayerWindow` initialization**:
   - Creates `VideoView` (NSView hosting Metal layer)
   - Initializes `MPVController` (libmpv wrapper)
   - Sets up controls (timeline, buttons, etc.)
   - Registers keyboard shortcut handler

3. **`PlayerWindow.mpvFileLoaded()`**:
   - Called when libmpv finishes loading file
   - Updates UI with video info, duration, tracks

#### Playback Control
1. **Keyboard input**: `PlayerWindow.keyDown(_:)` handles 20+ shortcuts
2. **UI controls**: Buttons trigger methods like `togglePlay()`, `seek(_:)`
3. **Menu actions**: Menu bar handles file open, settings, etc.

---

### 8.2 Windows Entry Points

#### Application Launch
1. **`main.cpp`**:
   - Creates `QApplication`
   - Sets up QSurfaceFormat (V-Sync, depth/stencil)
   - Configures palette (dark theme)
   - Checks for existing instance via IPC; if found, sends command and exits
   - Otherwise, creates primary instance with `QLocalServer`

2. **Single-Instance Pattern**:
   ```cpp
   QLocalServer server;
   if (!server.listen(serverName)) {
       qWarning() << "Failed to start IPC server";
   }
   MainWindow w;
   QObject::connect(&server, &QLocalServer::newConnection, &w, [&server, &w]() {
       QLocalSocket *socket = server.nextPendingConnection();
       // Read command and execute
   });
   ```

3. **`MainWindow` Initialization**:
   - Creates `MpvWidget` (Qt widget hosting libmpv)
   - Sets up UI controls (timeline, buttons, menus)
   - Initializes IPC command handler

#### Playback Control
1. **Keyboard input**: Qt key events via `MainWindow.keyPressEvent()`
2. **UI controls**: Qt signals/slots (e.g., `on_playButton_clicked()`)
3. **Slider interaction**: Custom `ClickableSlider` for direct timeline seeking

---

### 8.3 libmpv Event Loop Integration

#### macOS (`MPVController.swift`)
```swift
func startPlayback() {
    mpv_set_option_string(mpv_handle, "vo", "null")  // Disable mpv's window
    mpv_set_option_string(mpv_handle, "hwdec", "videotoolbox")
    
    // Set render context callback
    mpv_render_context_set_update_callback(render_ctx, mpvRenderUpdateCallback, ...)
    
    mpv_command_string(mpv_handle, "loadfile \(url)")
}
```

#### Windows (`main.cpp`)
```cpp
// Polling loop in separate thread
while (!shutdown) {
    mpv_event *event = mpv_wait_event(mpv, timeout);
    if (event) {
        if (event->event_id == MPV_EVENT_FILE_LOADED) {
            // Update UI
        }
    }
}
```

---

## 9. Quick Reference: Common Development Tasks

### Task: Add New Playback Property
1. **macOS**:
   - Add property to `VideoInfo` struct in `MPVController.swift`
   - Add observation: `mpv_observe_property(...)`
   - Update `mpvPropertyChanged(_:value:)` delegate method
   - Display in UI via `PlayerWindow`

2. **Windows**:
   - Add property member to `MainWindow` class
   - Add observation in `mpv` initialization
   - Handle in event loop (Qt slot)
   - Update UI via Qt property/signal

### Task: Add New Shader Preset
1. Add `.glsl` file to `shaders/` directory
2. Update `kShaderPresets` dictionary in `MPVController.swift` (macOS)
3. Update shader list in Windows settings (`SettingsWindow.cpp`)

### Task: Fix UI Bug
1. **macOS**: Locate in `PlayerWindow.swift` or relevant window controller
2. **Windows**: Locate in `.cpp` file (MainWindow.cpp, etc.); XAML for WinUI
3. Rebuild: `./build.sh` (macOS) or `cmake --build build-win-x64 --config Release` (Windows)

### Task: Improve Performance
1. **macOS**: Check `UniversalSilicon.swift` for QoS dispatch; consider moving heavy work to P-cores
2. **Windows**: Profile with Visual Studio Performance Profiler; check for UI thread blocking
3. **Both**: Monitor libmpv CPU usage with `stats` overlay (press `i`)

---

## 10. Debugging & Troubleshooting

### macOS Debugging

#### Build Issues
- **"Cannot find libmpv"**: `brew list mpv` to verify installation; add `-I /opt/homebrew/include` to swiftc flags
- **Icon generation fails**: Ensure `iconutil` present via `which iconutil`
- **Metal shader compilation error**: Check Shaders.metal syntax; run `xcrun metal -c Shaders.metal -o /tmp/test.air` manually

#### Runtime Issues
- **Black video**: Check `VideoView` layer setup; ensure `wantsLayer = true`
- **Audio not working**: Verify `ao=avfoundation` in mpv.conf; check system audio output device
- **App crashes on startup**: Check entitlements; re-run with JIT enabled: `xattr -cr "/Applications/Glass Player.app"`

### Windows Debugging

#### Build Issues
- **"Qt6 not found"**: Ensure Qt6 paths in CMAKE_PREFIX_PATH; run cmake with `-DCMAKE_PREFIX_PATH=<qt-install-path>`
- **libmpv download fails**: Manually run `python windows/download_mpv.py --arch x64`
- **MOC compilation error**: Delete `build-win-x64/` and reconfigure; MOC cache may be stale

#### Runtime Issues
- **"Cannot open video"**: Verify libmpv-2.dll in build directory; check file permissions
- **UI rendering glitches**: Disable V-Sync temporarily: comment out `format.setSwapInterval(1)`
- **Audio delay issues**: Adjust `audio-spdif` setting in mpv.conf; check system audio latency

---

## 11. Appendices

### A. Environment Variables

#### macOS
- `BUILD_PROFILE`: Set to `debug` for unoptimized builds (default: `optimized`)
- `NO_INSTALL`: Set to `1` to skip DMG creation
- `SKIP_SIGN`: Set to `1` to skip code signing

#### Windows
- `Qt_ROOT`: Path to Qt6 installation (if CMake cannot find it)
- `MSVC_RUNTIME`: Link against dynamic (`dynamic`) or static (`static`) MSVC runtime

### B. File Format Quick Reference

| Format | Support | Notes |
|--------|---------|-------|
| H.264 | ✅ Hardware (VideoToolbox/DXVA2) | Fast, broad compatibility |
| HEVC | ✅ Hardware | Modern standard; better compression |
| AV1 | ✅ Software | Requires fast CPU |
| VP9 | ✅ Software | YouTube format |
| ProRes | ✅ Hardware (VideoToolbox) | macOS-specific |
| **Audio** | | |
| AAC | ✅ Hardware | Standard |
| FLAC | ✅ Software | Lossless |
| DTS-HD Master Audio | ✅ Pass-through | Bitstream only |
| Dolby TrueHD | ✅ Pass-through | Requires SPDIF/eARC |
| Dolby Atmos | ✅ PCM multi-channel | Rendered by macOS/Windows |

### C. Performance Benchmarks (Target)

- **Startup time**: < 1 second
- **First frame**: < 500ms (with hardware decoding)
- **4K 60fps playback**: < 15% CPU (with hardware decoding)
- **Anime4K upscaling**: 60fps achievable on M2+; 30fps on M1

---

## 12. License & Attribution

- **Glass Player**: GPL-3.0 (due to libmpv and FFmpeg dependencies)
- **Anime4K Shaders**: MIT License
- **Third-party**: libmpv (GPL), FFmpeg (LGPL/GPL), Qt6 (LGPL)

---

**Document Version**: 1.0  
**Last Updated**: 2026-06-23  
**Maintained By**: Glass Player Development Team
