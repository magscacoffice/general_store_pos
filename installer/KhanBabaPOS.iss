#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Khan Baba POS"
#define AppPublisher "Khan Baba General Store"

[Setup]
AppId={{A7F8B1A4-3E90-4F63-8E8A-4F1F8B1A4C21}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\KhanBabaPOS
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\artifacts\installer
OutputBaseFilename=KhanBabaPOS-Setup-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
Uninstallable=yes
UninstallDisplayIcon={app}\KhanBabaPos.Wpf.exe
CloseApplications=yes
CloseApplicationsFilter=KhanBabaPos.Wpf.exe
RestartApplications=no
SetupLogging=yes
UsePreviousAppDir=yes
MinVersion=10.0.17763

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Dirs]
; Business data and backups are outside {app} and are explicitly retained on uninstall.
Name: "{localappdata}\KhanBabaPOS\Data"; Flags: uninsneveruninstall
Name: "{localappdata}\KhanBabaPOS\Backups"; Flags: uninsneveruninstall
Name: "{localappdata}\KhanBabaPOS\Updates"; Flags: uninsneveruninstall

[Files]
Source: "..\artifacts\publish\win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\KhanBabaPos.Wpf.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\KhanBabaPos.Wpf.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\KhanBabaPos.Wpf.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
