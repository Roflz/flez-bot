; Inno Setup script for flez-bot.
; Build: run installer_deps\download-installers.ps1, then iscc installer.iss (see PACKAGING.md).
; The installer bundles Git and Python installers, runs them silently if needed, copies the app,
; runs setup.ps1, and creates a shortcut.

#define MyAppName "flez-bot"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "flez-bot"
#define MyAppURL "https://github.com/your-org/flez-bot"
; Bundle dir: folder containing repo root (launcher.py, setup.ps1, bot_runelite_IL, runelite, flez-bot.exe).
; Default: current dir (repo root). Override: iscc /DBUNDLE_DIR=dist\flez-bot-bundle installer.iss
#ifndef BUNDLE_DIR
#define BUNDLE_DIR "."
#endif

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=flez-bot-setup-{#MyAppVersion}
SetupIconFile=packaging\icon.ico
UninstallDisplayIcon={app}\flez-bot.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Bundled Git and Python installers (run silently if needed). From installer_deps\ after running download-installers.ps1.
Source: "installer_deps\GitInstaller.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "installer_deps\PythonInstaller.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
; Copy entire bundle into {app}. Must include launcher.py, setup.ps1, bot_runelite_IL, runelite, and flez-bot.exe if built.
Source: "{#BUNDLE_DIR}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
; Install Git if not present (bundled installer).
Filename: "{tmp}\GitInstaller.exe"; Parameters: "/VERYSILENT /NORESTART /o:PathOption=Cmd"; StatusMsg: "Installing Git (if needed)..."; Check: GitNeeded; Flags: runhidden waituntilterminated
; Install Python 3.13 if not present (bundled installer).
Filename: "{tmp}\PythonInstaller.exe"; Parameters: "/quiet InstallAllUsers=0 PrependPath=1"; StatusMsg: "Installing Python (if needed)..."; Check: PythonNeeded; Flags: runhidden waituntilterminated
; Run full setup (submodules, PySide6). Use refreshed PATH so newly installed Git/Python are found.
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -NoProfile -Command ""$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User'); & '{app}\setup.ps1'"""; StatusMsg: "Running setup (submodules, PySide6)..."; Flags: runhidden waituntilterminated

[Icons]
; Start Menu and Desktop: Target = full path to exe, WorkingDir = install dir so launch works reliably.
; Use {userprograms} for a single shortcut in Start Menu root (no subfolder); {group} would create a "flez-bot" folder.
Name: "{userprograms}\{#MyAppName}.lnk"; Filename: "{app}\flez-bot.exe"; WorkingDir: "{app}"; Comment: "flez-bot launcher"; Check: LauncherExeExists
Name: "{userprograms}\{#MyAppName}.lnk"; Filename: "python"; Parameters: "launcher.py"; WorkingDir: "{app}"; Comment: "flez-bot launcher (Python)"; Check: LauncherExeMissing
Name: "{autodesktop}\{#MyAppName}.lnk"; Filename: "{app}\flez-bot.exe"; WorkingDir: "{app}"; Tasks: desktopicon; Comment: "flez-bot launcher"; Check: LauncherExeExists
Name: "{autodesktop}\{#MyAppName}.lnk"; Filename: "python"; Parameters: "launcher.py"; WorkingDir: "{app}"; Tasks: desktopicon; Comment: "flez-bot launcher (Python)"; Check: LauncherExeMissing

[Code]
function LauncherExeExists: Boolean;
begin
  Result := FileExists(ExpandConstant('{app}\flez-bot.exe'));
end;

function LauncherExeMissing: Boolean;
begin
  Result := not LauncherExeExists;
end;

function RunCommand(const Exe, Params: string; var ExitCode: Integer): Boolean;
var
  WorkDir: string;
begin
  WorkDir := ExpandConstant('{tmp}');
  Result := Exec(Exe, Params, WorkDir, SW_HIDE, ewWaitUntilTerminated, ExitCode);
end;

function GitInstalled: Boolean;
var
  ExitCode: Integer;
begin
  Result := RunCommand('cmd.exe', '/c git --version', ExitCode) and (ExitCode = 0);
end;

function PythonInstalled: Boolean;
var
  ExitCode: Integer;
begin
  if RunCommand('cmd.exe', '/c python --version', ExitCode) and (ExitCode = 0) then
    Result := True
  else if RunCommand('cmd.exe', '/c py -3 -c ""exit(0)""', ExitCode) and (ExitCode = 0) then
    Result := True
  else
    Result := False;
end;

function GitNeeded: Boolean;
begin
  Result := not GitInstalled;
end;

function PythonNeeded: Boolean;
begin
  Result := not PythonInstalled;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    if DirExists(ExpandConstant('{app}\installer_deps')) then
      DelTree(ExpandConstant('{app}\installer_deps'), True, True, True);
end;
