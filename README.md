# Glass Player

Glass Player is a lightweight, high-performance media player optimized for macOS and Windows. Engineered with native rendering backends and powered by libmpv, it is designed to deliver hardware-accelerated video decoding, precise color representation, and seamless integration with platform-specific display APIs.

On macOS, the player is written in Swift and leverages Metal 3 to exploit Apple Silicon's Unified Memory Architecture (UMA) via zero-copy frame buffer sharing. On Windows, it is built with modern C++ and Qt6, utilizing Direct3D 11 and Vulkan for robust GPU-accelerated rendering.

---

## Core Features

### High-Performance Rendering
* **macOS (Metal 3)**: Implements a zero-copy frame buffer object (FBO) pipeline using IOSurface. Video frames are shared between the libmpv decoder and the Metal renderer in unified memory, eliminating intermediate host-to-device memory copies.
* **Windows (Direct3D 11 / Vulkan)**: Integrates libmpv with the Qt6 OpenGL and hardware-accelerated graphics swap chains, automatically falling back to Direct3D 11 or Vulkan depending on the active GPU and hardware configuration.

### Video and Color Pipeline
* **High Dynamic Range (HDR)**: Native support for Dolby Vision, HDR10, and HLG content with precise color space conversions and tone mapping.
* **Real-time Upscaling**: Built-in integration of Anime4K shaders, enabling real-time high-quality upscaling directly inside the GPU rendering loop.

### High-Fidelity Audio
* Supports pass-through bitstreaming for advanced formats including Dolby Atmos, Dolby TrueHD, and DTS-HD Master Audio.

### Cloud Integration
* Built-in rclone mounting and streaming integration, allowing direct, low-latency playback of remote media files from cloud storage providers.

---

## System Requirements

| Platform | Operating System | Hardware Requirements |
|---|---|---|
| **macOS** | macOS 14.0 (Sonoma) or later | Apple Silicon (M1/M2/M3/M4/M5 series) |
| **Windows** | Windows 10 / 11 (64-bit or ARM64) | DirectX 11 or Vulkan compatible GPU |

---

## Architecture Overview

### macOS Zero-Copy Pipeline
```text
[libmpv Decoder / GPU Backend]
             │
             ▼ (Unified Memory Interface)
    [IOSurface Shared Buffer]
             │
             ▼ (Zero-Copy Texture Binding)
   [Metal 3 Render Pipeline] ──► [Display Swap Chain]
```
The macOS version avoids traditional PCIe bus transfer overhead by using Apple Silicon's Unified Memory Architecture. The decoder writes frames directly into an IOSurface buffer, which is immediately bound as a Metal texture, bypassing the CPU and memory copy cycles entirely.

### Windows C++/Qt6 Architecture
```text
[Qt6 Gui Application Thread]
             │
             ▼ (Inter-process Communication / Events)
    [libmpv Playback Core] ◄──► [Direct3D 11 / Vulkan Viewport]
```
The Windows version hosts the libmpv core within a dedicated rendering thread, synchronizing playback controls with the Qt6 event loop. Video presentation is offloaded directly to Direct3D 11 or Vulkan to minimize frame drops and UI latency.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Space` / `K` | Play / Pause |
| `F` | Toggle Fullscreen |
| `Escape` | Exit Fullscreen |
| `←` | Seek Backward 5s |
| `→` | Seek Forward 5s |
| `J` | Seek Backward 10s |
| `L` | Seek Forward 10s |
| `↑` | Volume Up |
| `↓` | Volume Down |
| `M` | Mute / Unmute |
| `S` | Cycle Subtitle Track |
| `A` / `Ctrl+A` | Cycle Audio Track |
| `Shift+A` | Cycle Aspect Ratio |
| `I` | Toggle Video Info Overlay |
| `,` | Frame Step Backward |
| `.` | Frame Step Forward |
| `[` | Speed Down (-0.25x) |
| `]` | Speed Up (+0.25x) |
| `;` | Audio Delay +100ms |
| `'` | Audio Delay -100ms |
| `\` | Reset Audio Delay |
| `Ctrl+]` / `Cmd+]` | Audio Delay +1ms (fine) |
| `Ctrl+[` / `Cmd+[` | Audio Delay -1ms (fine) |
| `Ctrl+K` / `Cmd+K` | Toggle/Cycle Anime4K Shaders |
| `Ctrl+Up` / `Cmd+Up` | Brightness Up |
| `Ctrl+Down` / `Cmd+Down` | Brightness Down |
| `Cmd/Ctrl+O` | Open File |
| `Cmd/Ctrl+U` | Open URL |
| `Cmd/Ctrl+,` | Open Settings |

---

## Installation

### macOS
1. Download the latest `GlassPlayer-macOS-arm64.dmg` from the Releases section.
2. Mount the disk image and run the installer script, or drag the application to the `Applications` directory.
3. If installing manually, clear the Gatekeeper quarantine attribute:
   ```bash
   xattr -cr "/Applications/Glass Player.app"
   ```

### Windows
1. Download either the `GlassPlayer-Windows-x64.exe` or `GlassPlayer-Windows-ARM64.exe` installer depending on your processor architecture.
2. Run the executable to launch the installer wizard.

---

## Building from Source

### macOS Prerequisites and Compilation
Ensure you have Xcode Command Line Tools and Homebrew installed.

1. Install the libmpv dependency:
   ```bash
   brew install mpv
   ```
2. Clone the repository and navigate to the macOS directory:
   ```bash
   git clone https://github.com/khr898/Glass-player-macOS.git
   cd Glass-player-macOS/macOS/GlassPlayer
   ```
3. Execute the build script:
   ```bash
   ./build.sh
   ```

### Windows Prerequisites and Compilation
Ensure you have Visual Studio 2022 (with the "Desktop development with C++" workload) and CMake 3.20 or later installed. For ARM64 builds, the MSVC ARM64 toolchain must also be selected in the Visual Studio Installer.

The build process will automatically download the correct `libmpv` developer binaries for your target architecture from SourceForge during the configuration step.

#### Building for Windows x64
1. Configure and generate the build files:
   ```powershell
   cmake -S windows -B build-win-x64 -G "Visual Studio 17 2022" -A x64
   ```
2. Compile the release binary:
   ```powershell
   cmake --build build-win-x64 --config Release
   ```

#### Building for Windows ARM64 (Cross-compilation or Native)
1. Configure and generate the build files:
   ```powershell
   cmake -S windows -B build-win-ARM64 -G "Visual Studio 17 2022" -A ARM64
   ```
2. Compile the release binary:
   ```powershell
   cmake --build build-win-ARM64 --config Release
   ```

---

## License

Glass Player is licensed under the GNU General Public License v3.0 (GPL-3.0), due to dependencies on libmpv and FFmpeg. The integrated Anime4K shaders are licensed under the MIT License.
