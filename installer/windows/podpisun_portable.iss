; One-file portable for USB sticks.
; Double-click on the flash drive -> extract next to this .exe -> launch.
; Stamps (pechatky.podpisun) stay on the flash drive with the app.

#define MyAppName "Підписун"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Підписун"
#define MyAppExeName "podpisun.exe"
#define MyAppDirName "Pidpysun"
#define SourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
; Extract beside the .exe on the USB (not into AppData).
DefaultDirName={src}\{#MyAppDirName}
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
DisableFinishedPage=yes
DisableWelcomePage=yes
CreateAppDir=yes
Uninstallable=no
CreateUninstallRegKey=no
UsePreviousAppDir=no
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=Pidpysun-{#MyAppVersion}-windows-portable
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=no
CloseApplications=no
RestartApplications=no
; Allow running from removable drives.
DiskSpanning=no

[Languages]
Name: "ukrainian"; MessagesFile: "compiler:Languages\Ukrainian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Code]
function PortableAppPath(): String;
begin
  Result := ExpandConstant('{src}\{#MyAppDirName}\{#MyAppExeName}');
end;

function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  { Already extracted on this USB — just start the app. }
  if FileExists(PortableAppPath()) then
  begin
    Exec(PortableAppPath(), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
    Result := False;
  end
  else
    Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssDone then
    Exec(ExpandConstant('{app}\{#MyAppExeName}'), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;
