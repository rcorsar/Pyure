#ifndef MyAppVersion
  #define MyAppVersion "0.1.2"
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
UninstallDisplayIcon={app}\pyure.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=yes
CloseApplicationsFilter=pyure.exe

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Pyure"; Filename: "{app}\pyure.exe"
Name: "{autodesktop}\Pyure"; Filename: "{app}\pyure.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\pyure.exe"; Description: "{cm:LaunchProgram,Pyure}"; Flags: nowait postinstall skipifsilent
