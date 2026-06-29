#define AppVersion "0.9.9"

[Setup]
AppName=PonyNotes
AppVersion={#AppVersion}
AppPublisher=PonyNotes
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\PonyNotes
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
Source: "AppFlowy\vc_redist_x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall
Source: "AppFlowy\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{userdesktop}\PonyNotes"; Filename: "{app}\PonyNotes.exe"
Name: "{group}\PonyNotes"; Filename: "{app}\PonyNotes.exe"

[Run]
Filename: "{tmp}\vc_redist_x64.exe"; Parameters: "/install /quiet /norestart"; Description: "Installing Visual C++ Redistributable..."; Flags: shellexec waituntilterminated
Filename: "{app}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; Description: "Installing WebView2 Runtime..."; Flags: shellexec waituntilterminated; StatusMsg: "Installing WebView2 Runtime..."

[Registry]
Root: HKCU; Subkey: "Software\Classes\ponynotes"; ValueType: "string"; ValueData: "URL:PonyNotes"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ponynotes"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\ponynotes\DefaultIcon"; ValueType: "string"; ValueData: "{app}\PonyNotes.exe,0"
Root: HKCU; Subkey: "Software\Classes\ponynotes\shell\open\command"; ValueType: "string"; ValueData: """{app}\PonyNotes.exe"" ""%1"""
