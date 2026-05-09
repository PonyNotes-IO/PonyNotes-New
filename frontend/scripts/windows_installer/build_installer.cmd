@echo off
chcp 65001 >nul

echo =============================================
echo   PonyNotes Windows Installer Builder
echo =============================================
echo.

REM Get script directory
set "SCRIPT_DIR=%~dp0"
set "FRONTEND_DIR=%SCRIPT_DIR%..\.."
set "RUST_LIB_DIR=%FRONTEND_DIR%\rust-lib"
set "FLUTTER_DIR=%FRONTEND_DIR%\appflowy_flutter"
set "DART_FFI_SOURCE=%RUST_LIB_DIR%\target\release\dart_ffi.dll"
set "DART_FFI_TARGET=%FLUTTER_DIR%\windows\flutter\dart_ffi\dart_ffi.dll"
set "DART_FFI_BACKUP=%SCRIPT_DIR%dart_ffi.dll.bak"
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

REM ============================================================================
REM Step 1: Build Rust library (dart_ffi.dll)
REM ============================================================================
echo.
echo [1/5] Building Rust library (dart_ffi.dll)...
cd /d "%RUST_LIB_DIR%"

REM Backup existing dart_ffi.dll if it exists
if exist "%DART_FFI_SOURCE%" (
    echo Backing up existing dart_ffi.dll...
    copy /Y "%DART_FFI_SOURCE%" "%DART_FFI_BACKUP%"
)

REM Build Rust library
echo Compiling Rust dart_ffi library...
cargo build --release -p dart-ffi
if %errorlevel% neq 0 (
    echo [ERROR] Rust build failed
    exit /b 1
)

REM Verify dart_ffi.dll was created
if not exist "%DART_FFI_SOURCE%" (
    echo [ERROR] dart_ffi.dll was not created after Rust build
    echo Expected location: %DART_FFI_SOURCE%
    exit /b 1
)
echo [OK] Rust library built successfully

REM ============================================================================
REM Step 2: Prepare Flutter project (copy dart_ffi.dll before clean)
REM ============================================================================
echo.
echo [2/5] Preparing Flutter project...

REM Create target directory if it doesn't exist
if not exist "%FLUTTER_DIR%\windows\flutter\dart_ffi" mkdir "%FLUTTER_DIR%\windows\flutter\dart_ffi"

REM Copy dart_ffi.dll to Flutter source directory (required for CMake)
echo Copying dart_ffi.dll to Flutter source...
copy /Y "%DART_FFI_SOURCE%" "%DART_FFI_TARGET%" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Failed to copy dart_ffi.dll to Flutter project
    exit /b 1
)
echo [OK] dart_ffi.dll copied to Flutter project

REM ============================================================================
REM Step 3: Build Flutter Release
REM ============================================================================
echo.
echo [3/5] Building Flutter Release...
cd /d "%FLUTTER_DIR%"

echo Getting dependencies...
flutter pub get
echo Done getting dependencies

echo Building Flutter Windows Release...
echo Starting build at %TIME%
flutter build windows --release
echo Build command finished with code %errorlevel%
if %errorlevel% neq 0 (
    echo [ERROR] Flutter Release build failed
    exit /b 1
)

REM Verify build output
if not exist "%FLUTTER_DIR%\build\windows\x64\runner\Release\PonyNotes.exe" (
    echo [ERROR] Flutter build failed - PonyNotes.exe not found
    exit /b 1
)
echo [OK] Flutter Release build completed

REM ============================================================================
REM Step 4: Prepare installation directory
REM ============================================================================
echo.
echo [4/5] Preparing installation directory...

REM Clean old installation directory
if exist "%INSTALL_DIR%" rmdir /s /q "%INSTALL_DIR%" 2>nul
mkdir "%INSTALL_DIR%"

REM Copy Flutter build artifacts (root files)
echo Copying Flutter build files...
for %%f in ("%FLUTTER_DIR%\build\windows\x64\runner\Release\*.*") do (
    copy "%%f" "%INSTALL_DIR%\" /Y >nul
)

REM Copy Flutter build subdirectories (data, etc.)
if exist "%FLUTTER_DIR%\build\windows\x64\runner\Release\data" (
    echo Copying data directory...
    xcopy "%FLUTTER_DIR%\build\windows\x64\runner\Release\data" "%INSTALL_DIR%\data\" /E /I /Y >nul
)

REM Verify data directory was copied (required for Flutter)
if not exist "%INSTALL_DIR%\data" (
    echo [ERROR] data directory is missing! This is required for the app to run.
    echo Please run: flutter build windows --release
    exit /b 1
)
echo [OK] data directory verified

REM Verify app.so exists
if not exist "%INSTALL_DIR%\data\app.so" (
    echo [ERROR] app.so is missing! Flutter build may have failed.
    exit /b 1
)
echo [OK] app.so verified

REM Verify icudtl.dat exists (critical for Flutter)
if not exist "%INSTALL_DIR%\data\icudtl.dat" (
    echo [ERROR] icudtl.dat is missing! This is required for the app to run.
    if exist "%FLUTTER_DIR%\build\windows\x64\runner\Release\data\icudtl.dat" (
        echo Attempting to copy icudtl.dat...
        copy "%FLUTTER_DIR%\build\windows\x64\runner\Release\data\icudtl.dat" "%INSTALL_DIR%\data\" /Y >nul
        if not exist "%INSTALL_DIR%\data\icudtl.dat" (
            echo [ERROR] Failed to copy icudtl.dat
            exit /b 1
        )
    ) else (
        echo [ERROR] icudtl.dat not found in Flutter build output
        exit /b 1
    )
)
echo [OK] icudtl.dat verified

REM Verify flutter_assets exists
if not exist "%INSTALL_DIR%\data\flutter_assets" (
    echo [ERROR] flutter_assets is missing! This is required for the app to run.
    exit /b 1
)
echo [OK] flutter_assets verified

REM Clean up any old AppFlowy files if they exist (for backward compatibility)
if exist "%INSTALL_DIR%\AppFlowy.exe" del "%INSTALL_DIR%\AppFlowy.exe"
if exist "%INSTALL_DIR%\AppFlowy.exp" del "%INSTALL_DIR%\AppFlowy.exp"
if exist "%INSTALL_DIR%\AppFlowy.lib" del "%INSTALL_DIR%\AppFlowy.lib"

REM Copy Flutter plugin DLLs
echo Copying Flutter plugin DLLs...
for %%f in ("%FLUTTER_DIR%\build\windows\x64\plugins\*\*\Release\*.dll") do (
    if exist "%%f" copy "%%f" "%INSTALL_DIR%\" /Y >nul
)

REM Copy ANGLE DLLs (required for video playback)
echo Copying ANGLE DLLs...
if exist "%FLUTTER_DIR%\build\windows\x64\ANGLE\*.dll" (
    xcopy "%FLUTTER_DIR%\build\windows\x64\ANGLE\*.dll" "%INSTALL_DIR%\" /Y >nul
)

REM Copy libmpv DLL (required for video playback)
echo Copying libmpv DLL...
if exist "%FLUTTER_DIR%\build\windows\x64\libmpv\*.dll" (
    xcopy "%FLUTTER_DIR%\build\windows\x64\libmpv\*.dll" "%INSTALL_DIR%\" /Y >nul
)

REM Copy pdfium DLL
echo Copying pdfium DLL...
if exist "%FLUTTER_DIR%\build\windows\x64\.lib\chromium" (
    for %%f in ("%FLUTTER_DIR%\build\windows\x64\.lib\chromium\*\x64\pdfium.dll") do (
        if exist "%%f" copy "%%f" "%INSTALL_DIR%\" /Y >nul
    )
)

REM Copy dart_ffi.dll (main application library)
echo Copying dart_ffi.dll...
if exist "%DART_FFI_SOURCE%" (
    copy /Y "%DART_FFI_SOURCE%" "%INSTALL_DIR%\" >nul
) else if exist "%DART_FFI_TARGET%" (
    copy /Y "%DART_FFI_TARGET%" "%INSTALL_DIR%\" >nul
)
if not exist "%INSTALL_DIR%\dart_ffi.dll" (
    echo [WARNING] dart_ffi.dll not found in installation directory
)

REM Copy Rust DLL dependencies
echo Copying Rust DLL dependencies...
for %%f in ("%RUST_LIB_DIR%\target\release\deps\*.dll") do (
    if exist "%%f" copy "%%f" "%INSTALL_DIR%\" /Y >nul
)

REM Copy additional necessary files
if exist "%RUST_LIB_DIR%\target\release\*.dll" (
    for %%f in ("%RUST_LIB_DIR%\target\release\*.dll") do (
        copy "%%f" "%INSTALL_DIR%\" /Y >nul
    )
)

REM Copy VC++ Redistributable
echo Copying VC++ Redistributable...
if exist "%SCRIPT_DIR%vc_redist_x64.exe" (
    copy "%SCRIPT_DIR%vc_redist_x64.exe" "%INSTALL_DIR%\" /Y >nul
)

echo [OK] Installation directory ready

REM Final check before compilation
if not exist "%INSTALL_DIR%\data\app.so" (
    echo [ERROR] data directory is incomplete
    exit /b 1
)
if not exist "%INSTALL_DIR%\data\icudtl.dat" (
    echo [ERROR] icudtl.dat is missing from data directory
    exit /b 1
)
if not exist "%INSTALL_DIR%\data\flutter_assets" (
    echo [ERROR] flutter_assets is missing from data directory
    exit /b 1
)
echo [OK] All critical files verified

REM ============================================================================
REM Step 5: Compile installer
REM ============================================================================
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

REM Cleanup backup file
if exist "%DART_FFI_BACKUP%" del "%DART_FFI_BACKUP%"

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
