# Glass Player Conventions

## Code Style & Language
- macOS: Swift, Metal API best practices.
- Windows: C++20 (`windows-winui` utilizes C++/WinRT projections).
- Avoid raw pointer handling; use smart pointers (`std::unique_ptr`, `std::shared_ptr`, `winrt::com_ptr`).

## Architecture & Threading
- Keep heavy rendering and decoder operations (libmpv) off the UI main thread.
- WinUI 3: Use XAML code-behind for UI and dispatch updates to the main thread via `DispatcherQueue`.

## Graphics & Shaders
- Native hardware acceleration is crucial.
- Anime4K shaders integrated directly into the GPU pipeline.
- macOS leverages unified memory (zero-copy IOSurface).
- WinUI utilizes ANGLE OpenGL ES to Direct3D translation layer.
