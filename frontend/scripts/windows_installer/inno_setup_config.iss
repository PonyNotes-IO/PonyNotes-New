#define AppVersion "0.9.9"

[Setup]
AppName=PonyNotes
AppVersion={#AppVersion}
AppPublisher=PonyNotes
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
DefaultDirName={autopf}\PonyNotes\
DefaultGroupName=PonyNotes
SetupIconFile=app_icon.ico
UninstallDisplayIcon={app}\PonyNotes.exe
UninstallDisplayName=PonyNotes
VersionInfoVersion={#AppVersion}
UsePreviousAppDir=no
OutputBaseFilename=PonyNotesSetup
OutputDir=Output

[Files]
Source: "AppFlowy\PonyNotes.exe"; DestDir: "{app}"; DestName: "PonyNotes.exe"; Flags: ignoreversion
Source: "AppFlowy\vc_redist_x64.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "AppFlowy\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{userdesktop}\PonyNotes"; Filename: "{app}\PonyNotes.exe"
Name: "{group}\PonyNotes"; Filename: "{app}\PonyNotes.exe"

[Run]
Filename: "{app}\vc_redist_x64.exe"; Parameters: "/install /quiet /norestart"; Description: "Installing Visual C++ Redistributable..."; Flags: shellexec waituntilterminated

[Registry]
Root: HKCR; Subkey: "PonyNotes"; ValueType: "string"; ValueData: "URL:Custom Protocol"; Flags: uninsdeletekey
Root: HKCR; Subkey: "PonyNotes"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""
Root: HKCR; Subkey: "PonyNotes\DefaultIcon"; ValueType: "string"; ValueData: "{app}\PonyNotes.exe,0"
Root: HKCR; Subkey: "PonyNotes\shell\open\command"; ValueType: "string"; ValueData: """{app}\PonyNotes.exe"" ""%1"""
