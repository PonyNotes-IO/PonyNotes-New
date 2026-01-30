@echo off
chcp 65001 >nul

echo =============================================
echo   PonyNotes Windows Installer Builder
echo =============================================
echo.

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "FRONTEND_DIR=%SCRIPT_DIR%..\.."
set "INSTALL_DIR=%SCRIPT_DIR%AppFlowy"
set "OUTPUT_DIR=%SCRIPT_DIR%Output"

REM Set version
set "VERSION=0.9.9"

REM Set Inno Setup compiler path
set "ISCC_PATH=D:\Inno Setup 6\ISCC.exe"
if exist "%ISCC_PATH%" goto :found_iscc
    where iscc >nul 2>&1
    if %errorlevel% equ 0 (
        set "ISCC_PATH=iscc"
        goto :found_iscc
    )
    echo [ERROR] Inno Setup compiler (iscc.exe) not found
    echo Please install Inno Setup: https://jrsoftware.org/isdl.php
    exit /b 1
:found_iscc
echo [OK] Inno Setup compiler found

echo.
echo [2/5] Checking Flutter Release build...
set "FLUTTER_EXE=%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\runner\Release\PonyNotes.exe"
if not exist "%FLUTTER_EXE%" (
    echo [WARNING] Flutter Release build not found
    echo Automatically building Release version...
    echo.
    cd /d "%FRONTEND_DIR%\appflowy_flutter"
    flutter clean
    echo Cleaning up cached files...
    powershell -Command "Remove-Item -Path '%FRONTEND_DIR%\appflowy_flutter\build' -Recurse -Force -ErrorAction SilentlyContinue"
    flutter pub get
    flutter build windows --release
    if %errorlevel% neq 0 (
        echo [ERROR] Flutter Release build failed
        exit /b 1
    )
    if not exist "%FLUTTER_EXE%" (
        echo [ERROR] Flutter Release build failed - executable not found
        exit /b 1
    )
    echo.
    echo [OK] Flutter Release build completed
    cd /d "%SCRIPT_DIR%"
)
echo [OK] Flutter Release build found

echo.
echo [3/5] Checking Rust Release build...
set "RUST_DLL=%FRONTEND_DIR%\rust-lib\target\release\deps\*.dll"
if not exist "%RUST_DLL%" (
    echo [WARNING] Rust Release DLL not found, will use existing dependencies
)
echo [OK] Rust build check complete

echo.
echo [4/5] Preparing installation directory...
REM Clean old installation directory
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%" 2>nul
mkdir "%INSTALL_DIR%"

REM Copy Flutter build artifacts
echo Copying Flutter artifacts...
xcopy "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\runner\Release\*" "%INSTALL_DIR%\" /E /H /Y >nul

REM Verify data directory was copied (required for Flutter)
if not exist "%INSTALL_DIR%\data" (
    echo [ERROR] data directory is missing! This is required for the app to run.
    echo Please run: flutter build windows --release
    exit /b 1
)
echo [OK] data directory verified

REM Remove AppFlowy.exe to avoid confusion, keep only PonyNotes.exe
if exist "%INSTALL_DIR%\AppFlowy.exe" del "%INSTALL_DIR%\AppFlowy.exe"
if exist "%INSTALL_DIR%\AppFlowy.exp" del "%INSTALL_DIR%\AppFlowy.exp"
if exist "%INSTALL_DIR%\AppFlowy.lib" del "%INSTALL_DIR%\AppFlowy.lib"

REM Copy Flutter plugin DLLs
echo Copying Flutter plugin DLLs...
for %%f in ("%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\plugins\*\*\Release\*.dll") do (
    if exist "%%f" copy "%%f" "%INSTALL_DIR%\" /Y >nul
)

REM Copy ANGLE DLLs (required for video playback)
echo Copying ANGLE DLLs...
if exist "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\ANGLE\*.dll" (
    xcopy "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\ANGLE\*.dll" "%INSTALL_DIR%\" /Y >nul
)

REM Copy libmpv DLL (required for video playback)
echo Copying libmpv DLL...
if exist "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\libmpv\*.dll" (
    xcopy "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\libmpv\*.dll" "%INSTALL_DIR%\" /Y >nul
)

REM Copy pdfium DLL
echo Copying pdfium DLL...
if exist "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\.lib\chromium" (
    for %%f in ("%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\.lib\chromium\*\x64\pdfium.dll") do (
        if exist "%%f" copy "%%f" "%INSTALL_DIR%\" /Y >nul
    )
)

REM Copy Rust DLL dependencies
echo Copying Rust DLL dependencies...
for %%f in ("%FRONTEND_DIR%\rust-lib\target\release\deps\*.dll") do (
    if exist "%%f" copy "%%f" "%INSTALL_DIR%\" /Y >nul
)

REM Copy additional necessary files
if exist "%FRONTEND_DIR%\rust-lib\target\release\*.dll" (
    for %%f in ("%FRONTEND_DIR%\rust-lib\target\release\*.dll") do (
        copy "%%f" "%INSTALL_DIR%\" /Y >nul
    )
)

REM Copy VC++ Redistributable
echo Copying VC++ Redistributable...
if exist "%SCRIPT_DIR%vc_redist_x64.exe" (
    copy "%SCRIPT_DIR%vc_redist_x64.exe" "%INSTALL_DIR%\" /Y >nul
)

echo [OK] Installation directory ready

REM Ensure data directory exists (required for Flutter app)
if not exist "%INSTALL_DIR%\data" (
    echo [WARNING] data directory missing, copying from Flutter build...
    xcopy "%FRONTEND_DIR%\appflowy_flutter\build\windows\x64\runner\Release\data" "%INSTALL_DIR%\data\" /E /H /Y >nul
    if not exist "%INSTALL_DIR%\data" (
        echo [ERROR] Failed to copy data directory
        exit /b 1
    )
)

REM Final check before compilation
if not exist "%INSTALL_DIR%\data\app.so" (
    echo [ERROR] data directory is incomplete
    exit /b 1
)

echo.
echo [5/5] Compiling installer...
REM Clean old output directory
if exist "%OUTPUT_DIR%" rmdir /s /q "%OUTPUT_DIR%" 2>nul
mkdir "%OUTPUT_DIR%"

REM Compile
"%ISCC_PATH%" "%SCRIPT_DIR%inno_setup_config.iss"
if %errorlevel% equ 0 (
    echo [OK] Installer compiled successfully!
) else (
    echo [ERROR] Installer compilation failed
    exit /b 1
)

echo.
echo =============================================
echo   Build Complete!
echo =============================================
echo.
echo Installer location: %OUTPUT_DIR%
echo.
if exist "%OUTPUT_DIR%\PonyNotesSetup.exe" (
    echo [OK] Installer: %OUTPUT_DIR%\PonyNotesSetup.exe
    echo.
    echo Size:
    for %%I in ("%OUTPUT_DIR%\PonyNotesSetup.exe") do echo   - %%~zI bytes
) else (
    echo [WARNING] PonyNotesSetup.exe not found
)
echo.
