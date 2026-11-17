; =============================================================================
; WSL Control Panel - the Setup wizard (Inno Setup 6).
;
; Built by build\build-setup.ps1 (on GitHub for every release), which
; passes AppVersion, Stage (the folder with the app's files) and Icon.
; Screens: Welcome -> where to install -> shortcuts -> Finish. On a first install the
; folder box starts empty: the user must choose (Browse or type) where the app
; goes. Updates reuse the folder chosen then and skip that page.
; Installs for the current user only, so Windows asks for no administrator
; rights. Uninstall: Settings > Apps.
;
; Keep this file plain ASCII.
; =============================================================================

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Stage
  #define Stage "..\release\stage"
#endif
#ifndef Icon
  #define Icon "..\release\app.ico"
#endif
#ifndef OutDir
  #define OutDir "..\release"
#endif

#define AppName "WSL Control Panel"
#define AppExe "WSL Control Panel.exe"

[Setup]
; Never change AppId: Windows uses it to recognise updates of the same app.
AppId={{11AE9744-F39D-4894-85B0-0C6FC37A1F67}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=ssn-26
AppPublisherURL=https://github.com/ssn-26/wsl-setup-and-run-helper
AppSupportURL=https://github.com/ssn-26/wsl-setup-and-run-helper/issues
AppUpdatesURL=https://github.com/ssn-26/wsl-setup-and-run-helper/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={localappdata}\Programs\{#AppName}
UsePreviousAppDir=yes
DirExistsWarning=no
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
MinVersion=10.0
WizardStyle=modern
SetupIconFile={#Icon}
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
OutputDir={#OutDir}
OutputBaseFilename=WSL-Control-Panel-Setup
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel2=This installs [name/ver] on your computer.%n%nIt lets you install and run Linux on Windows (WSL) from simple buttons - no commands to type.%n%nNo administrator rights are needed.
SelectDirLabel3=Choose where to put the app. Your Linux distros and backups are not stored here - the app asks you where to keep them.
SelectDirBrowseLabel=Click Browse to pick a folder (a "WSL Control Panel" folder is made inside it), or type a full path. Then click Next.
FinishedLabel=WSL Control Panel is installed. You can open it any time from the Start menu or the desktop.

[InstallDelete]
; Files of older versions (and of the PowerShell install line) that are no
; longer used, and the app's own folder (replaced by the new version's).
; Your data folder (saved logins and settings) is never touched.
Type: filesandordirs; Name: "{app}\app"
Type: filesandordirs; Name: "{app}\powershell"
Type: filesandordirs; Name: "{app}\bash"
Type: filesandordirs; Name: "{app}\launcher"
Type: files; Name: "{app}\WSL-Control-Panel.bat"
Type: files; Name: "{app}\Install.bat"
Type: files; Name: "{app}\install.ps1"
Type: files; Name: "{app}\README.md"
Type: files; Name: "{app}\LICENSE"

[Files]
Source: "{#Stage}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
; On by default. An update keeps the choice made the first time.
Name: "desktopicon"; Description: "Put a shortcut on the desktop"; GroupDescription: "Shortcuts (the Start menu always gets one):"

[Icons]
Name: "{userprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Comment: "Open, manage and back up your WSL Linux distros"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Comment: "Open, manage and back up your WSL Linux distros"; Tasks: desktopicon

[Registry]
; The Settings > Apps entry of the PowerShell install line, replaced by this one.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\WSLControlPanel"; ValueType: none; Flags: deletekey dontcreatekey

[Run]
Filename: "{app}\{#AppExe}"; Description: "Open WSL Control Panel"; Flags: postinstall nowait skipifsilent
; An update started from the app runs silently and opens the app again.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: ShouldRelaunch

[Code]
var
  DirCleared: Boolean;

function ShouldRelaunch: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:relaunch|0}') = '1');
end;

// No default folder: on a first install the folder box starts empty, so the
// user picks where the app goes. (DefaultDirName above is only used by a
// silent install without /DIR.) An update already knows its folder and does
// not show this page.
procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpSelectDir) and not DirCleared then
  begin
    DirCleared := True;
    // Not when a folder was given (/DIR=...) or the install is silent: then
    // the folder is already chosen, and clearing it would stop the install.
    if (WizardForm.PrevAppDir = '') and (ExpandConstant('{param:DIR|}') = '') and not WizardSilent then
      WizardForm.DirEdit.Text := '';
  end;
end;

// Folders like Program Files need administrator rights: say so on the folder
// page instead of failing halfway through the install.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  Dir, Probe: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then
  begin
    Dir := Trim(WizardForm.DirEdit.Text);
    if Dir = '' then
    begin
      MsgBox('Please choose where to install the app: click Browse and pick a folder, or type a full path such as' + #13#10 +
        'D:\Apps\WSL Control Panel', mbInformation, MB_OK);
      Result := False;
      Exit;
    end;
    Dir := WizardDirValue;
    Probe := AddBackslash(Dir) + '.wsl-control-panel-write-test';
    if not ForceDirectories(Dir) or not SaveStringToFile(Probe, '', False) then
    begin
      MsgBox('Windows does not let this app write to' + #13#10 + Dir + #13#10#13#10 +
        'Folders like Program Files need administrator rights. Please choose a folder ' +
        'in your user folder or on another drive (or keep the suggested one).', mbError, MB_OK);
      Result := False;
    end
    else
      DeleteFile(Probe);
  end;
end;

// Uninstall removes the app. Your saved logins and settings go only if you
// say so; Linux distros and backups are never here, so they are never touched.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Data: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    Data := ExpandConstant('{app}\data');
    if DirExists(Data + '\config') and not UninstallSilent then
    begin
      if MsgBox('Also delete your saved logins and settings?' + #13#10#13#10 + Data + '\config' + #13#10#13#10 +
          'Your Linux distros and backups are not affected either way.', mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        DelTree(Data + '\config', True, True, True);
        DelTree(Data + '\logs', True, True, True);
      end;
    end;
    RemoveDir(Data);
    RemoveDir(ExpandConstant('{app}'));
  end;
end;
