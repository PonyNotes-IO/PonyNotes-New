; 版本号优先取命令行 /DAppVersion=xxx(CI 传入),此处仅为本地调试兜底
#ifndef AppVersion
#define AppVersion "0.9.9"
#endif

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
; CI 产物目录为 PonyNotes(见 PonyNotes-Builder windows.yaml 拷贝步骤);
; vc_redist_x64.exe 与本 .iss 同目录(由 windows_installer/* 一起拷贝)
Source: "PonyNotes\PonyNotes.exe"; DestDir: "{app}"; DestName: "PonyNotes.exe"; Flags: ignoreversion
Source: "vc_redist_x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall
Source: "PonyNotes\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{userdesktop}\PonyNotes"; Filename: "{app}\PonyNotes.exe"
Name: "{group}\PonyNotes"; Filename: "{app}\PonyNotes.exe"

[Run]
Filename: "{tmp}\vc_redist_x64.exe"; Parameters: "/install /quiet /norestart"; Description: "Installing Visual C++ Redistributable..."; Flags: shellexec waituntilterminated
; skipifdoesntexist:产物中当前未捆绑 WebView2 引导器,存在才执行,避免安装时报错
Filename: "{app}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; Description: "Installing WebView2 Runtime..."; Flags: shellexec waituntilterminated skipifdoesntexist; StatusMsg: "Installing WebView2 Runtime..."

[Registry]
Root: HKCU; Subkey: "Software\Classes\ponynotes"; ValueType: "string"; ValueData: "URL:PonyNotes"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\ponynotes"; ValueType: "string"; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\ponynotes\DefaultIcon"; ValueType: "string"; ValueData: "{app}\PonyNotes.exe,0"
Root: HKCU; Subkey: "Software\Classes\ponynotes\shell\open\command"; ValueType: "string"; ValueData: """{app}\PonyNotes.exe"" ""%1"""
