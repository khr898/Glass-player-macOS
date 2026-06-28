# Glass Player Suggested Commands

## Windows WinUI 3 Build & Run
- Setup dependencies (downloads libmpv & ANGLE):
  ```powershell
  python windows-winui/download_dependencies.py --arch x64
  ```
- Restore NuGet packages:
  ```powershell
  msbuild windows-winui/windows-winui.vcxproj -t:restore
  ```
- Build project (Debug x64):
  ```powershell
  msbuild windows-winui/windows-winui.vcxproj /p:Configuration=Debug /p:Platform=x64
  ```
- Run executable:
  ```powershell
  .\build\x64\Debug\windows-winui.exe
  ```

## macOS Build
- Build from script:
  ```bash
  cd macOS/GlassPlayer && ./build.sh
  ```

## System / Utility Commands (Windows PowerShell)
- Search for files:
  ```powershell
  Get-ChildItem -Recurse -Filter *.cpp
  ```
- Search for text patterns in code:
  ```powershell
  Select-String -Path ".\windows-winui\*.cpp" -Pattern "some_pattern"
  ```
