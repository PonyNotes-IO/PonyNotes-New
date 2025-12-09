@echo off
REM Register custom URL protocol ponynotes:// to launch the AppFlowy executable.
REM Usage: register_ponynotes_protocol.bat "C:\Program Files\AppFlowy\AppFlowy.exe"

if "%~1"=="" (
  echo [ERROR] Missing AppFlowy.exe path. Usage:
  echo   %~nx0 "C:\Program Files\AppFlowy\AppFlowy.exe"
  exit /b 1
)

set "APPFLOWY_EXE=%~1"

reg add "HKEY_CLASSES_ROOT\ponynotes" /ve /d "URL:ponynotes" /f
reg add "HKEY_CLASSES_ROOT\ponynotes" /v "URL Protocol" /d "" /f
reg add "HKEY_CLASSES_ROOT\ponynotes\shell" /f
reg add "HKEY_CLASSES_ROOT\ponynotes\shell\open" /f
reg add "HKEY_CLASSES_ROOT\ponynotes\shell\open\command" /ve /d "\"%APPFLOWY_EXE%\" \"%%1\"" /f

echo Registered ponynotes:// with %APPFLOWY_EXE%

