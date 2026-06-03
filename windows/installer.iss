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
