; Windows installer: Inno Setup script that packs the release build into
; Vaultify-Setup.exe. Built by .github/workflows/build.yml on a version tag,
; or locally with:
;   flutter build windows --release
;   iscc windows\packaging\vaultify.iss /DAppVersion=1.0.0

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Vaultify"
#define AppPublisher "Vaultify"
#define AppExeName "vaultify.exe"

; Where `flutter build windows --release` leaves the app bundle.
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; AppId must never change, or upgrades install side by side instead of replacing.
AppId={{8F3C21D4-7B6E-4A58-9C1F-2E5D40A7B913}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir=..\..\build\installer
OutputBaseFilename=Vaultify-Setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Windows 10 64-bit and up, per SPEC.md.
MinVersion=10.0
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Installs per user by default, so no admin prompt; the dialog offers all-users.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The whole Flutter bundle: exe, DLLs and the data folder with fonts and assets.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The vault itself lives in the user's app data folder and is deliberately
; left in place, so uninstalling never destroys someone's passwords.
Type: dirifempty; Name: "{app}"
