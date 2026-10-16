; Lumora installer script (Inno Setup 6)
#define AppName "Lumora"
#define AppVersion "1.3.8"
#define AppExe "Lumora.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{7B1E3C52-5A0D-4F5C-9E2B-4C6F1A9D3E71}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Lumora
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=output
OutputBaseFilename=Lumora-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "portuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
; Used by the in-app updater: it runs the installer silently with /LAUNCH=1 to reopen Lumora afterwards.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: WantsLaunch

[Code]
function WantsLaunch: Boolean;
begin
  Result := ExpandConstant('{param:LAUNCH|0}') = '1';
end;
