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
Source: "PonyNotes\PonyNotes.exe"; DestDir: "{app}"; DestName: "PonyNotes.exe"; Flags: ignoreversion
; Note: vc_redist_x64.exe is optional - uncomment if you have it
; Source: "PonyNotes\vc_redist_x64.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "PonyNotes\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{userdesktop}\PonyNotes"; Filename: "{app}\PonyNotes.exe"
Name: "{group}\PonyNotes"; Filename: "{app}\PonyNotes.exe"

[Run]
; Note: vc_redist_x64.exe is optional - uncomment if you have it
; Filename: "{app}\vc_redist_x64.exe"; Parameters: "/install /quiet /norestart"; Description: "Installing Visual C++ Redistributable..."; Flags: shellexec waituntilterminated

[Registry]
Root: HKCU; Subkey: "Software\Classes\ponynotes"; ValueType: "string"; ValueData: "URL:PonyNotes"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ponynotes"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\ponynotes\DefaultIcon"; ValueType: "string"; ValueData: "{app}\PonyNotes.exe,0"
Root: HKCU; Subkey: "Software\Classes\ponynotes\shell\open\command"; ValueType: "string"; ValueData: """{app}\PonyNotes.exe"" ""%1"""
