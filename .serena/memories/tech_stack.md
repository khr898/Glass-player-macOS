# Glass Player Tech Stack

## Platforms & Frameworks

### macOS
- Languages: Swift
- Graphics API: Metal 3
- Native Buffering: IOSurface (Unified Memory Architecture, zero-copy FBO sharing)
- Playback Decoder: libmpv (Homebrew dependency)

### Windows (WinUI 3) — Active
- Languages: C++ (C++20, CppWinRT)
- Frameworks: Windows App SDK 1.6, Win2D 1.3, Windows Implementation Library (WIL)
- Graphics Translation: ANGLE (OpenGL ES API mapped to Direct3D 11 backend)
- Playback Decoder: libmpv

## Shared & Third-party
- Upscaling: Anime4K shaders (MIT License)
- Network/Streaming: rclone integration
