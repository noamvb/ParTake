; Inno Setup script for the Windows installer. The release workflow runs:
;   iscc /DAppVersion=0.7.0 /DBuildDir=<repo>\build\windows\x64\runner\Release windows\installer\partake.iss
; Installs per user (no administrator prompt) with a Start menu shortcut.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Fixed so a new version installs over the old one.
AppId={{6F1B7D0E-3C52-4C8A-9E4B-2B7F5A1D9C30}
AppName=ParTake
AppVersion={#AppVersion}
AppPublisher=noamvb
AppPublisherURL=https://github.com/noamvb/ParTake
AppUpdatesURL=https://github.com/noamvb/ParTake/releases
DefaultDirName={autopf}\ParTake
DefaultGroupName=ParTake
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=ParTake-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\partake.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\ParTake"; Filename: "{app}\partake.exe"
Name: "{autodesktop}\ParTake"; Filename: "{app}\partake.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\partake.exe"; Description: "{cm:LaunchProgram,ParTake}"; Flags: nowait postinstall skipifsilent
