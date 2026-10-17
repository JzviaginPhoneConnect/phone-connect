; PhoneConnect installer (Inno Setup 6).
; Built by build/build-windows.ps1, which passes:
;   /DAppVersion=1.2.3  /DFileVersion=1.2.3.0  /DStage=<staged app files>  /DOutDir=<dist folder>
; The stage folder holds the app files plus tools-x64\ and tools-arm64\;
; the installer copies the right tools for the PC (Intel/AMD or ARM, e.g.
; Windows in Parallels on an Apple Silicon Mac) into {app}\tools.

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
#ifndef FileVersion
  #define FileVersion "0.0.0.0"
#endif

[Setup]
AppId={{BEA4A542-F1EC-43F7-86E6-037D1C3139DE}
AppName=PhoneConnect
AppVersion={#AppVersion}
AppVerName=PhoneConnect {#AppVersion}
; shown in the installer's Properties -> Details and in "Apps & features"
VersionInfoVersion={#FileVersion}
VersionInfoProductVersion={#FileVersion}
VersionInfoProductTextVersion={#AppVersion}
VersionInfoDescription=PhoneConnect {#AppVersion} Setup
AppPublisher=PhoneConnect
AppComments=Mirror and control your Android phone from your computer
; Per-user install: no admin rights needed
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\PhoneConnect
DisableDirPage=auto
DisableProgramGroupPage=yes
OutputDir={#OutDir}
OutputBaseFilename=PhoneConnect-Setup
SetupIconFile={#Stage}\PhoneConnect.ico
UninstallDisplayIcon={app}\PhoneConnect.exe
UninstallDisplayName=PhoneConnect {#AppVersion}
ArchitecturesAllowed=x64compatible arm64
ArchitecturesInstallIn64BitMode=x64compatible arm64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; adb (or the app's zsh) may still be running from a previous version; let Setup close it
CloseApplications=force

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#Stage}\PhoneConnect.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\PhoneConnect.sh";  DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\platform\*";      DestDir: "{app}\platform"; Flags: ignoreversion recursesubdirs
Source: "{#Stage}\shell\*";         DestDir: "{app}\shell";    Flags: ignoreversion recursesubdirs
Source: "{#Stage}\PhoneConnect.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\README.txt";       DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\licenses\*";      DestDir: "{app}\licenses"; Flags: ignoreversion recursesubdirs
Source: "{#Stage}\tools-x64\*";   DestDir: "{app}\tools"; Check: not IsArm64; Flags: ignoreversion recursesubdirs
Source: "{#Stage}\tools-arm64\*"; DestDir: "{app}\tools"; Check: IsArm64;     Flags: ignoreversion recursesubdirs

[InstallDelete]
; clear files from an older version before copying the new ones
Type: filesandordirs; Name: "{app}\tools"
Type: filesandordirs; Name: "{app}\platform"
Type: filesandordirs; Name: "{app}\shell"
Type: filesandordirs; Name: "{app}\licenses"
Type: files; Name: "{app}\PhoneConnect.ps1"
Type: files; Name: "{app}\.unblocked-*"

[Icons]
Name: "{autoprograms}\PhoneConnect"; Filename: "{app}\PhoneConnect.exe"; IconFilename: "{app}\PhoneConnect.ico"
Name: "{autodesktop}\PhoneConnect"; Filename: "{app}\PhoneConnect.exe"; IconFilename: "{app}\PhoneConnect.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\PhoneConnect.exe"; Description: "Start PhoneConnect now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; stop adb so its files can be removed
Filename: "{app}\tools\adb.exe"; Parameters: "kill-server"; Flags: runhidden; RunOnceId: "StopAdb"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\tools"
Type: filesandordirs; Name: "{app}\platform"
Type: filesandordirs; Name: "{app}\shell"
Type: files; Name: "{app}\.unblocked-*"
