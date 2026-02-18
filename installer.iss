; Inno Setup bootstrap installer for flez-bot.
; Installs bootstrap launcher/updater/runtime scripts only, then downloads app artifact.

#define MyAppName "flez-bot"
#ifndef MyAppVersion
#define MyAppVersion "0.1.0"
#endif
#define MyAppPublisher "flez-bot"
#define MyAppURL "https://github.com/Roflz/flez-bot"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={code:GetDefaultInstallDir}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=FlezBotSetup
SetupIconFile=packaging\icon.ico
UninstallDisplayIcon={app}\flez-bot.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Bootstrap runtime components only (not the full app payload).
Source: "flez-bot.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "launcher.py"; DestDir: "{app}"; Flags: ignoreversion
Source: "updater.py"; DestDir: "{app}"; Flags: ignoreversion
Source: "install-runtime.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "app_version.txt"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -File ""{app}\install-runtime.ps1"" -InstallDir ""{app}"" -Channel ""{code:GetChannelArg}"""; StatusMsg: "Installing flez-bot..."; Flags: runhidden waituntilterminated logoutput

[Icons]
Name: "{userprograms}\{#MyAppName}.lnk"; Filename: "{app}\flez-bot.exe"; WorkingDir: "{app}"; Comment: "flez-bot launcher"
Name: "{autodesktop}\{#MyAppName}.lnk"; Filename: "{app}\flez-bot.exe"; WorkingDir: "{app}"; Tasks: desktopicon; Comment: "flez-bot launcher"

[Code]
function GetDefaultInstallDir(Value: string): string;
begin
  if IsAdminInstallMode then
    Result := ExpandConstant('{autopf}\{#MyAppName}')
  else
    Result := ExpandConstant('{localappdata}\{#MyAppName}');
end;

function GetChannelArg(Value: string): string;
begin
  Result := 'alpha';
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  SetupLog: string;
begin
  if CurStep = ssDone then begin
    SetupLog := ExpandConstant('{app}\logs\install.log');
    if FileExists(SetupLog) then
      MsgBox(
        'flez-bot installed successfully.' + #13#10 + #13#10 +
        'Details are in:' + #13#10 + SetupLog,
        mbInformation, MB_OK
      );
  end;
end;
