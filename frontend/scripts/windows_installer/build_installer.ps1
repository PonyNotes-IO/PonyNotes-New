# PonyNotes Windows Installer Builder
# Compatible with PowerShell execution environment

$ErrorActionPreference = "Continue"

Write-Host "============================================="
Write-Host "  PonyNotes Windows Installer Builder"
Write-Host "============================================="
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrontendDir = Join-Path $ScriptDir "..\.."
$RustLibDir = Join-Path $FrontendDir "rust-lib"
$FlutterDir = Join-Path $FrontendDir "appflowy_flutter"
$InstallDir = Join-Path $ScriptDir "AppFlowy"
$OutputDir = Join-Path $ScriptDir "Output"

$Version = "0.9.9"

# Detect Inno Setup compiler
$IsccPath = "D:\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $IsccPath)) {
    $iscc = Get-Command iscc -ErrorAction SilentlyContinue
    if ($iscc) {
        $IsccPath = $iscc.Source
    }
}
if (-not (Test-Path $IsccPath)) {
    Write-Host "[ERROR] Inno Setup compiler (iscc.exe) not found" -ForegroundColor Red
    Write-Host "Please install Inno Setup: https://jrsoftware.org/isdl.php"
    exit 1
}
Write-Host "[OK] Inno Setup compiler found: $IsccPath"

# ============================================================================
# Step 1: Build Flutter Release
# ============================================================================
Write-Host ""
Write-Host "[1/3] Building Flutter Release..."

Push-Location $FlutterDir

Write-Host "Getting dependencies..."
# Suppress stderr deprecation warnings that confuse PowerShell
flutter pub get 2>$null
$pubCode = $LASTEXITCODE
Write-Host "Done getting dependencies (exit code: $pubCode)"
if ($pubCode -ne 0) {
    Write-Host "[ERROR] flutter pub get failed with code $pubCode" -ForegroundColor Red
    Pop-Location
    exit $pubCode
}

Write-Host "Building Flutter Windows Release..."
Write-Host "Starting build at $(Get-Date -Format 'HH:mm:ss')"
flutter build windows --release 2>$null
$buildCode = $LASTEXITCODE
Write-Host "Build command finished with code: $buildCode"
Pop-Location

if ($buildCode -ne 0) {
    Write-Host "[ERROR] Flutter Release build failed with code $buildCode" -ForegroundColor Red
    exit $buildCode
}

$exePath = Join-Path $FlutterDir "build\windows\x64\runner\Release\PonyNotes.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "[ERROR] Flutter build failed - PonyNotes.exe not found at $exePath" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Flutter Release build completed: $exePath"

# ============================================================================
# Step 2: Prepare installation directory
# ============================================================================
Write-Host ""
Write-Host "[2/3] Preparing installation directory..."

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$releaseDir = Join-Path $FlutterDir "build\windows\x64\runner\Release"

Write-Host "Copying Flutter build files..."
Copy-Item "$releaseDir\*" $InstallDir -Force -ErrorAction SilentlyContinue

Write-Host "Copying data directory..."
$dataDir = Join-Path $releaseDir "data"
if (Test-Path $dataDir) {
    Copy-Item "$dataDir\*" "$InstallDir\data" -Recurse -Force
}

# Verify critical files
if (-not (Test-Path "$InstallDir\data")) {
    Write-Host "[ERROR] data directory is missing!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] data directory verified"

if (-not (Test-Path "$InstallDir\data\app.so")) {
    Write-Host "[ERROR] app.so is missing!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] app.so verified"

$icudtlSrc = Join-Path $dataDir "icudtl.dat"
$icudtlDst = Join-Path $InstallDir "data\icudtl.dat"
if (-not (Test-Path $icudtlDst)) {
    if (Test-Path $icudtlSrc) {
        Copy-Item $icudtlSrc $icudtlDst -Force
    }
}
if (-not (Test-Path $icudtlDst)) {
    Write-Host "[ERROR] icudtl.dat is missing!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] icudtl.dat verified"

if (-not (Test-Path "$InstallDir\data\flutter_assets")) {
    Write-Host "[ERROR] flutter_assets is missing!" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] flutter_assets verified"

# Clean old AppFlowy compatibility files
Remove-Item "$InstallDir\AppFlowy.exe" -Force -ErrorAction SilentlyContinue
Remove-Item "$InstallDir\AppFlowy.exp" -Force -ErrorAction SilentlyContinue
Remove-Item "$InstallDir\AppFlowy.lib" -Force -ErrorAction SilentlyContinue

# Copy Flutter plugin DLLs
Write-Host "Copying Flutter plugin DLLs..."
$pluginDlls = Get-ChildItem "$FlutterDir\build\windows\x64\plugins\*\*\Release\*.dll" -ErrorAction SilentlyContinue
foreach ($dll in $pluginDlls) {
    Copy-Item $dll.FullName $InstallDir -Force -ErrorAction SilentlyContinue
}

# Copy ANGLE DLLs
Write-Host "Copying ANGLE DLLs..."
$angleDir = Join-Path $FlutterDir "build\windows\x64\ANGLE"
if (Test-Path $angleDir) {
    Copy-Item "$angleDir\*.dll" $InstallDir -Force -ErrorAction SilentlyContinue
}

# Copy libmpv DLL
Write-Host "Copying libmpv DLL..."
$mpvDir = Join-Path $FlutterDir "build\windows\x64\libmpv"
if (Test-Path $mpvDir) {
    Copy-Item "$mpvDir\*.dll" $InstallDir -Force -ErrorAction SilentlyContinue
}

# Copy pdfium DLL
Write-Host "Copying pdfium DLL..."
$pdfiumBase = Join-Path $FlutterDir "build\windows\x64\.lib\chromium"
if (Test-Path $pdfiumBase) {
    $pdfiumDlls = Get-ChildItem "$pdfiumBase\*\x64\pdfium.dll" -ErrorAction SilentlyContinue
    foreach ($dll in $pdfiumDlls) {
        Copy-Item $dll.FullName $InstallDir -Force -ErrorAction SilentlyContinue
    }
}

# Copy dart_ffi.dll from Flutter build output
Write-Host "Copying dart_ffi.dll..."
$dartFfiFromBuild = Join-Path $releaseDir "dart_ffi.dll"
$dartFfiFromSrc = Join-Path $FlutterDir "windows\flutter\dart_ffi\dart_ffi.dll"
if (Test-Path $dartFfiFromBuild) {
    Copy-Item $dartFfiFromBuild "$InstallDir\dart_ffi.dll" -Force
    Write-Host "[OK] dart_ffi.dll copied from Flutter build output"
} elseif (Test-Path $dartFfiFromSrc) {
    Copy-Item $dartFfiFromSrc "$InstallDir\dart_ffi.dll" -Force
    Write-Host "[OK] dart_ffi.dll copied from source"
} else {
    Write-Host "[WARNING] dart_ffi.dll not found in build output or source" -ForegroundColor Yellow
}

# Copy Rust DLL dependencies
Write-Host "Copying Rust DLL dependencies..."
$rustDeps = Join-Path $RustLibDir "target\release\deps"
if (Test-Path $rustDeps) {
    Copy-Item "$rustDeps\*.dll" $InstallDir -Force -ErrorAction SilentlyContinue
}
$rustDlls = Join-Path $RustLibDir "target\release"
if (Test-Path $rustDlls) {
    Copy-Item "$rustDlls\*.dll" $InstallDir -Force -ErrorAction SilentlyContinue
}

# Copy VC++ Redistributable
Write-Host "Copying VC++ Redistributable..."
$vcRedist = Join-Path $ScriptDir "vc_redist_x64.exe"
if (Test-Path $vcRedist) {
    Copy-Item $vcRedist $InstallDir -Force
}

Write-Host "[OK] Installation directory ready"

# Final check
if (-not (Test-Path "$InstallDir\data\app.so") -or
    -not (Test-Path "$InstallDir\data\icudtl.dat") -or
    -not (Test-Path "$InstallDir\data\flutter_assets")) {
    Write-Host "[ERROR] Installation directory is incomplete" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] All critical files verified"

# ============================================================================
# Step 3: Compile installer
# ============================================================================
Write-Host ""
Write-Host "[3/3] Compiling installer..."

if (Test-Path $OutputDir) {
    Remove-Item $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$issFile = Join-Path $ScriptDir "inno_setup_config.iss"
if (-not (Test-Path $issFile)) {
    Write-Host "[ERROR] Inno Setup config not found: $issFile" -ForegroundColor Red
    exit 1
}

Write-Host "Running: $IsccPath $issFile"
& $IsccPath $issFile
$issCode = $LASTEXITCODE

if ($issCode -eq 0) {
    Write-Host "[OK] Installer compiled successfully!" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Installer compilation failed with code $issCode" -ForegroundColor Red
    exit $issCode
}

Write-Host ""
Write-Host "============================================="
Write-Host "  Build Complete!"
Write-Host "============================================="
Write-Host ""
Write-Host "Installer location: $OutputDir"
Write-Host ""

$setupExe = Join-Path $OutputDir "PonyNotesSetup.exe"
if (Test-Path $setupExe) {
    $size = [math]::Round((Get-Item $setupExe).Length / 1MB, 2)
    Write-Host "[OK] Installer: $setupExe"
    Write-Host "     Size: $size MB"
} else {
    Write-Host "[WARNING] PonyNotesSetup.exe not found in $OutputDir" -ForegroundColor Yellow
}
Write-Host ""
