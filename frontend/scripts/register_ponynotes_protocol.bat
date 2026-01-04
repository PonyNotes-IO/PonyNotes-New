@echo off
REM Register a custom URL protocol to launch the App executable.
REM Usage: register_ponynotes_protocol.bat "C:\Path\To\App.exe" [protocol_name]
REM Example: register_ponynotes_protocol.bat "C:\Program Files\AppFlowy\AppFlowy.exe" appflowy

if "%~1"=="" (
  echo [ERROR] Missing app executable path. Usage:
  echo   %~nx0 "C:\Path\To\App.exe" [protocol_name]
  exit /b 1
)

set "APP_EXE=%~1"
set "PROTO=%~2"
if "%PROTO%"=="" set "PROTO=appflowy"

echo Registering protocol "%PROTO%://" for executable: %APP_EXE%

reg add "HKEY_CLASSES_ROOT\%PROTO%" /ve /d "URL:%PROTO% Protocol" /f
reg add "HKEY_CLASSES_ROOT\%PROTO%" /v "URL Protocol" /d "" /f
reg add "HKEY_CLASSES_ROOT\%PROTO%\shell" /f
reg add "HKEY_CLASSES_ROOT\%PROTO%\shell\open" /f
reg add "HKEY_CLASSES_ROOT\%PROTO%\shell\open\command" /ve /d "\"%APP_EXE%\" \"%%1\"" /f

if %ERRORLEVEL% EQU 0 (
  echo Registered %PROTO%:// successfully.
) else (
  echo [ERROR] Failed to register protocol %PROTO%://
)
