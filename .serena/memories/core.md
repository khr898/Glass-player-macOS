# Glass Player Core

High-performance, lightweight media player optimized for macOS and Windows. Uses libmpv decoder.

## Source Map
- `macOS/` - Swift/Metal 3 implementation for Apple Silicon (zero-copy IOSurface).
- `windows/` - C++/Qt6 implementation (legacy, superseded by windows-winui).
- `windows-winui/` - C++/WinUI 3 (Windows App SDK) implementation (ANGLE OpenGL ES to D3D11 backend).
- `shaders/` - Custom Anime4K upscaling shaders.
- `vendor/` - Third-party libraries (libmpv, ANGLE).

## Project Invariants
- Platforms: macOS (14+ Sonoma or later), Windows (10/11 64-bit or ARM64).
- High Performance: Low latency, hardware-accelerated video decoding.
- Audio: High-fidelity audio pass-through bitstreaming.
- Cloud Integration: rclone mounting and streaming.

## Navigation
- Technology Stack: `mem:tech_stack`
- Suggested Commands: `mem:suggested_commands`
- Conventions: `mem:conventions`
- Task Completion: `mem:task_completion`
