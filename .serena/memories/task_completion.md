# Glass Player Task Completion Checklist

## Compilation Check
- Verify the build succeeds cleanly (no error codes) using MSBuild or CMake.
- If dependencies were added/changed, ensure `download_dependencies.py` has been updated and executed.

## Runtime Validation
- Launch the target binary (e.g. `.\build\x64\Debug\windows-winui.exe`).
- Ensure video files and URLs open and play smoothly.
- Test basic control hotkeys (Space for play/pause, arrows for seeking, Volume controls).
- Open Settings and rclone views to verify they function properly.

## Clean Up
- Remove temporary build artifacts, scratch scripts, or uncommitted files not meant for version control.
