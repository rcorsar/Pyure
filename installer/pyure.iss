#ifndef MyAppVersion
  #define MyAppVersion "0.1.4"
#endif

[Setup]
AppId={{D9A6B54C-8C12-4F4A-9B83-3F5D9A0F1E22}
AppName=Pyure
AppVersion={#MyAppVersion}
AppVerName=Pyure {#MyAppVersion}
AppPublisher=Pyure
AppPublisherURL=https://github.com/rcorsar/Pyure
AppSupportURL=https://github.com/rcorsar/Pyure/issues
DefaultDirName={localappdata}\Programs\Pyure
DefaultGroupName=Pyure
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Pyure-{#MyAppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\pyure.ico
ChangesAssociations=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
CloseApplicationsFilter=pyure.exe
DirExistsWarning=no
RestartIfNeededByRun=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"
Type: files; Name: "{app}\*.ico"
Type: files; Name: "{app}\pyure.exe"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; DestName: "pyure.ico"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Pyure"; Filename: "{app}\pyure.exe"; IconFilename: "{app}\pyure.ico"
Name: "{autodesktop}\Pyure"; Filename: "{app}\pyure.exe"; IconFilename: "{app}\pyure.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\pyure.exe"; Description: "{cm:LaunchProgram,Pyure}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"
Type: files; Name: "{app}\*.ico"
Type: files; Name: "{app}\*.exe"
Type: files; Name: "{app}\*.dat"
Type: files; Name: "{app}\*.log"
Type: files; Name: "{app}\*.dmp"
Type: dirifempty; Name: "{app}"

[Code]
procedure KillRunningPyure();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM pyure.exe /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure RefreshShellIcons();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\ie4uinit.exe'), '-show', '', SW_HIDE, ewNoWait, ResultCode);
end;

function InitializeSetup(): Boolean;
begin
  KillRunningPyure();
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RefreshShellIcons();
  end;
end;

function InitializeUninstall(): Boolean;
begin
  KillRunningPyure();
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  AppDir: String;
  FolderName: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    KillRunningPyure();
  end
  else if CurUninstallStep = usPostUninstall then
  begin
    AppDir := RemoveBackslashUnlessRoot(ExpandConstant('{app}'));
    FolderName := ExtractFileName(AppDir);
    if (CompareText(FolderName, 'Pyure') = 0) and DirExists(AppDir) then
    begin
      Sleep(150);
      DelTree(AppDir, True, True, True);
    end;
    RefreshShellIcons();
  end;
end;
