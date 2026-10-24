#define MyAppName "Musify"
#define MyAppPublisher "Musify Contributors"
#define MyAppExeName "musify.exe"
#define MyAppUserModelID "com.gokadzev.musify"
#define MyAppVersion GetEnv("MUSIFY_VERSION")
#define RepoRoot "..\..\.."

[Setup]
AppId={{7DAA158B-0CC4-40BE-A10D-94823F73DF53}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#RepoRoot}\build\desktop-artifacts
OutputBaseFilename=Musify-windows-x64-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#RepoRoot}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; AppUserModelID: "{#MyAppUserModelID}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\{#MyAppExeName}"; AppUserModelID: "{#MyAppUserModelID}"; Tasks: desktopicon

[UninstallDelete]
Type: files; Name: "{app}\install-config.txt"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
const
  ConfigFileName = 'install-config.txt';

var
  LocationsPage: TInputDirWizardPage;
  LocationsConfirmed: Boolean;

function ConfigPath: String;
begin
  Result := ExpandConstant('{app}\' + ConfigFileName);
end;

function ReadConfigValue(const Key: String): String;
var
  Lines: TArrayOfString;
  I: Integer;
begin
  Result := '';
  if LoadStringsFromFile(ConfigPath, Lines) then
    for I := 0 to GetArrayLength(Lines) - 1 do
      if Pos(Key + '=', Lines[I]) = 1 then
        Result := Trim(Copy(Lines[I], Length(Key) + 2, MaxInt));
end;

function IsAbsolutePath(const Path: String): Boolean;
begin
  Result := (Copy(Path, 1, 2) = '\\') or
    ((Length(Path) >= 3) and (Path[2] = ':') and ((Path[3] = '\') or (Path[3] = '/')));
end;

procedure InitializeWizard;
begin
  LocationsPage := CreateInputDirPage(wpSelectDir,
    'Data locations',
    'Where should Musify keep your data?',
    'Application data holds playlists, liked songs, history and settings. ' +
    'Downloads holds saved music and artwork. Leave a field empty to use the default. ' +
    'Avoid folders synced by OneDrive or similar services. ' +
    'Existing data is copied to a new data folder and the original is kept.',
    False, '');
  LocationsPage.Add('Application data folder:');
  LocationsPage.Add('Downloads folder:');
  LocationsPage.Values[0] := ExpandConstant('{param:DATADIR|}');
  LocationsPage.Values[1] := ExpandConstant('{param:DOWNLOADSDIR|}');
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = LocationsPage.ID) and not LocationsConfirmed then
  begin
    if LocationsPage.Values[0] = '' then
      LocationsPage.Values[0] := ReadConfigValue('dataDir');
    if LocationsPage.Values[1] = '' then
      LocationsPage.Values[1] := ReadConfigValue('downloadsDir');
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  if CurPageID = LocationsPage.ID then
  begin
    for I := 0 to 1 do
    begin
      LocationsPage.Values[I] := Trim(LocationsPage.Values[I]);
      if (LocationsPage.Values[I] <> '') and not IsAbsolutePath(LocationsPage.Values[I]) then
      begin
        MsgBox('Enter a full folder path such as D:\Musify, or leave the field empty.', mbError, MB_OK);
        Result := False;
        Exit;
      end;
    end;
    LocationsConfirmed := True;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Lines: TArrayOfString;
  DataDir, DownloadsDir: String;
begin
  if CurStep <> ssPostInstall then Exit;
  if LocationsConfirmed then
  begin
    DataDir := LocationsPage.Values[0];
    DownloadsDir := LocationsPage.Values[1];
  end
  else
  begin
    // Silent installs keep earlier choices unless the command line gives new ones.
    DataDir := Trim(ExpandConstant('{param:DATADIR|}'));
    DownloadsDir := Trim(ExpandConstant('{param:DOWNLOADSDIR|}'));
    if DataDir = '' then DataDir := ReadConfigValue('dataDir');
    if DownloadsDir = '' then DownloadsDir := ReadConfigValue('downloadsDir');
  end;
  SetArrayLength(Lines, 2);
  Lines[0] := 'dataDir=' + DataDir;
  Lines[1] := 'downloadsDir=' + DownloadsDir;
  SaveStringsToUTF8File(ConfigPath, Lines, False);
end;
