#define AppName "Glass Player"
#define AppPublisher "Glass Player Team"
#define AppURL "https://github.com/khr898/Glass-player-macOS"
#define AppExeName "GlassPlayer.exe"

[Setup]
AppId={{E681C3F7-3B2E-4C07-BC63-0C507BE4C978}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile=..\LICENSE
OutputDir=.
OutputBaseFilename=GlassPlayer-{#AppVersion}-Windows-{#AppArch}
SetupIconFile=icons\app.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\bin\{#AppExeName}
#if AppArch == "x64"
ArchitecturesInstallIn64BitMode=x64compatible
#elif AppArch == "ARM64"
ArchitecturesInstallIn64BitMode=arm64
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startmenuicon"; Description: "Create a Start Menu shortcut"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "dist\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\bin\{#AppExeName}"; Tasks: startmenuicon
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"; Tasks: startmenuicon
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\bin\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\bin\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Registry]
; Register ProgID for Glass Player Video Files (HKA is HKLM/HKCU based on install mode)
Root: HKA; Subkey: "Software\Classes\GlassPlayer.VideoFile"; ValueType: string; ValueValue: "Glass Player Video File"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\GlassPlayer.VideoFile\DefaultIcon"; ValueType: string; ValueValue: "{app}\bin\{#AppExeName},0"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\GlassPlayer.VideoFile\shell\open\command"; ValueType: string; ValueValue: """{app}\bin\{#AppExeName}"" ""%1"""; Flags: uninsdeletekey

; Register the native Windows Video Thumbnail Provider for our associated ProgID
Root: HKA; Subkey: "Software\Classes\GlassPlayer.VideoFile\ShellEx\{{e357fccd-a995-4576-b01f-234630154e96}"; ValueType: string; ValueValue: "{{c5a40261-cd64-4ccf-84cb-c394da41d590}"; Flags: uninsdeletekey

; Associate standard video extensions with our ProgID under OpenWithProgids
Root: HKA; Subkey: "Software\Classes\.mp4\OpenWithProgids"; ValueType: string; ValueName: "GlassPlayer.VideoFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mkv\OpenWithProgids"; ValueType: string; ValueName: "GlassPlayer.VideoFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.avi\OpenWithProgids"; ValueType: string; ValueName: "GlassPlayer.VideoFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mov\OpenWithProgids"; ValueType: string; ValueName: "GlassPlayer.VideoFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.wmv\OpenWithProgids"; ValueType: string; ValueName: "GlassPlayer.VideoFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.webm\OpenWithProgids"; ValueType: string; ValueName: "GlassPlayer.VideoFile"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.flv\OpenWithProgids"; ValueType: string; ValueName: "GlassPlayer.VideoFile"; Flags: uninsdeletevalue
