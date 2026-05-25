# PonyNotes Windows Installer Builder (PowerShell)
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrontendDir = Join-Path $ScriptDir "..\.."
$RustLibDir = Join-Path $FrontendDir "rust-lib"
$FlutterDir = Join-Path $FrontendDir "appflowy_flutter"
$DartFfiSource = Join-Path $RustLibDir "target\release\dart_ffi.dll"
$DartFfiTarget = Join-Path $FlutterDir "windows\flutter\dart_ffi\dart_ffi.dll"
$DartFfiBackup = Join-Path $ScriptDir "dart_ffi.dll.bak"
$InstallDir = Join-Path $ScriptDir "AppFlowy"
$OutputDir = Join-Path $ScriptDir "Output"
$Version = "0.9.9"

# Find Inno Setup compiler
$IsccPath = "D:\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $IsccPath)) {
    $iscc = Get-Command iscc -ErrorAction SilentlyContinue
    if ($iscc) {
        $IsccPath = $iscc.Source
    } else {
        Write-Host "[ERROR] Inno Setup compiler (iscc.exe) not found" -ForegroundColor Red
        Write-Host "Please install Inno Setup: https://jrsoftware.org/isdl.php"
        exit 1
    }
}
Write-Host "[OK] Inno Setup compiler found: $IsccPath"

# ============================================================================
# Step 1: Build Rust library (dart_ffi.dll)
# ============================================================================
Write-Host ""
Write-Host "[1/5] Building Rust library (dart_ffi.dll)..."

Push-Location $RustLibDir

# Backup existing dart_ffi.dll if it exists
if (Test-Path $DartFfiSource) {
    Write-Host "Backing up existing dart_ffi.dll..."
    Copy-Item $DartFfiSource $DartFfiBackup -Force
}

# Build Rust library
Write-Host "Compiling Rust dart_ffi library..."
cargo build --release -p dart-ffi
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Rust build failed" -ForegroundColor Red
    Pop-Location
    exit 1
}

# Verify dart_ffi.dll was created
if (-not (Test-Path $DartFfiSource)) {
    Write-Host "[ERROR] dart_ffi.dll was not created after Rust build" -ForegroundColor Red
    Write-Host "Expected location: $DartFfiSource"
    Pop-Location
    exit 1
}
Write-Host "[OK] Rust library built successfully" -ForegroundColor Green

Pop-Location

# ============================================================================
# Step 2: Prepare Flutter project (copy dart_ffi.dll before clean)
# ============================================================================
Write-Host ""
Write-Host "[2/5] Preparing Flutter project..."

# Create target directory if it doesn't exist
$DartFfiDir = Split-Path -Parent $DartFfiTarget
if (-not (Test-Path $DartFfiDir)) {
    New-Item -ItemType Directory -Path $DartFfiDir -Force | Out-Null
}

# Copy dart_ffi.dll to Flutter source directory (required for CMake)
Write-Host "Copying dart_ffi.dll to Flutter source..."
Copy-Item $DartFfiSource $DartFfiTarget -Force
if (-not (Test-Path $DartFfiTarget)) {
    Write-Host "[ERROR] Failed to copy dart_ffi.dll to Flutter project" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] dart_ffi.dll copied to Flutter project" -ForegroundColor Green

# ============================================================================
# Step 3: Build Flutter Release
# ============================================================================
Write-Host ""
Write-Host "[3/5] Building Flutter Release..."

Push-Location $FlutterDir

Write-Host "Getting dependencies..."
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] flutter pub get failed" -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "[OK] Dependencies ready"

Write-Host "Building Flutter Windows Release..."
Write-Host "Starting build at $(Get-Date -Format 'HH:mm:ss')"
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Flutter Release build failed" -ForegroundColor Red
    Pop-Location
    exit 1
}
Write-Host "[OK] Flutter Release build completed" -ForegroundColor Green

Pop-Location

# Verify build output
$ExePath = Join-Path $FlutterDir "build\windows\x64\runner\Release\PonyNotes.exe"
if (-not (Test-Path $ExePath)) {
    Write-Host "[ERROR] Flutter build failed - PonyNotes.exe not found" -ForegroundColor Red
    exit 1
}

# ============================================================================
# Step 4: Prepare installation directory
# ============================================================================
Write-Host ""
Write-Host "[4/5] Preparing installation directory..."

# Clean old installation directory
if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Copy Flutter build artifacts
Write-Host "Copying Flutter build files..."
$ReleaseDir = Join-Path $FlutterDir "build\windows\x64\runner\Release"
Get-ChildItem $ReleaseDir -File | ForEach-Object {
    Copy-Item $_.FullName $InstallDir\ -Force
}

# Copy Flutter build subdirectories (data, etc.)
$DataDir = Join-Path $ReleaseDir "data"
if (Test-Path $DataDir) {
    Write-Host "Copying data directory..."
    Copy-Item $DataDir "$InstallDir\data\" -Recurse -Force
}

# Verify data directory was copied (required for Flutter)
if (-not (Test-Path "$InstallDir\data")) {
    Write-Host "[ERROR] data directory is missing! This is required for the app to run." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] data directory verified" -ForegroundColor Green

# Verify app.so exists
if (-not (Test-Path "$InstallDir\data\app.so")) {
    Write-Host "[ERROR] app.so is missing! Flutter build may have failed." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] app.so verified" -ForegroundColor Green

# Verify icudtl.dat exists (critical for Flutter)
if (-not (Test-Path "$InstallDir\data\icudtl.dat")) {
    $SourceIcu = Join-Path $DataDir "icudtl.dat"
    if (Test-Path $SourceIcu) {
        Write-Host "Attempting to copy icudtl.dat..."
        Copy-Item $SourceIcu "$InstallDir\data\" -Force
    }
    if (-not (Test-Path "$InstallDir\data\icudtl.dat")) {
        Write-Host "[ERROR] icudtl.dat is missing! This is required for the app to run." -ForegroundColor Red
        exit 1
    }
}
Write-Host "[OK] icudtl.dat verified" -ForegroundColor Green

# Verify flutter_assets exists
if (-not (Test-Path "$InstallDir\data\flutter_assets")) {
    Write-Host "[ERROR] flutter_assets is missing! This is required for the app to run." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] flutter_assets verified" -ForegroundColor Green

# Clean up any old AppFlowy files if they exist (for backward compatibility)
$OldFiles = @("AppFlowy.exe", "AppFlowy.exp", "AppFlowy.lib")
foreach ($file in $OldFiles) {
    $path = Join-Path $InstallDir $file
    if (Test-Path $path) {
        Remove-Item $path -Force
    }
}

# Copy Flutter plugin DLLs
Write-Host "Copying Flutter plugin DLLs..."
$PluginsDir = Join-Path $FlutterDir "build\windows\x64\plugins"
if (Test-Path $PluginsDir) {
    Get-ChildItem $PluginsDir -Recurse -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName $InstallDir\ -Force
    }
}

# Copy ANGLE DLLs (required for video playback)
Write-Host "Copying ANGLE DLLs..."
$AngleDir = Join-Path $FlutterDir "build\windows\x64\ANGLE"
if (Test-Path $AngleDir) {
    Get-ChildItem $AngleDir -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName $InstallDir\ -Force
    }
}

# Copy libmpv DLL (required for video playback)
Write-Host "Copying libmpv DLL..."
$LibmpvDir = Join-Path $FlutterDir "build\windows\x64\libmpv"
if (Test-Path $LibmpvDir) {
    Get-ChildItem $LibmpvDir -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName $InstallDir\ -Force
    }
}

# Copy pdfium DLL
Write-Host "Copying pdfium DLL..."
$ChromiumDir = Join-Path $FlutterDir "build\windows\x64\.lib\chromium"
if (Test-Path $ChromiumDir) {
    Get-ChildItem $ChromiumDir -Recurse -Filter "pdfium.dll" | ForEach-Object {
        Copy-Item $_.FullName $InstallDir\ -Force
    }
}

# Copy dart_ffi.dll (main application library)
Write-Host "Copying dart_ffi.dll..."
if (Test-Path $DartFfiSource) {
    Copy-Item $DartFfiSource $InstallDir\ -Force
} elseif (Test-Path $DartFfiTarget) {
    Copy-Item $DartFfiTarget $InstallDir\ -Force
}
if (-not (Test-Path "$InstallDir\dart_ffi.dll")) {
    Write-Host "[WARNING] dart_ffi.dll not found in installation directory" -ForegroundColor Yellow
}

# Copy Rust DLL dependencies
Write-Host "Copying Rust DLL dependencies..."
$RustDepsDir = Join-Path $RustLibDir "target\release\deps"
if (Test-Path $RustDepsDir) {
    Get-ChildItem $RustDepsDir -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName $InstallDir\ -Force
    }
}

# Copy additional necessary files
$RustDllDir = Join-Path $RustLibDir "target\release"
if (Test-Path $RustDllDir) {
    Get-ChildItem $RustDllDir -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName $InstallDir\ -Force
    }
}

# Copy VC++ Redistributable
Write-Host "Copying VC++ Redistributable..."
$VcRedist = Join-Path $ScriptDir "vc_redist_x64.exe"
if (Test-Path $VcRedist) {
    Copy-Item $VcRedist $InstallDir\ -Force
}

Write-Host "[OK] Installation directory ready" -ForegroundColor Green

# Final check before compilation
if (-not (Test-Path "$InstallDir\data\app.so")) {
    Write-Host "[ERROR] data directory is incomplete" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path "$InstallDir\data\icudtl.dat")) {
    Write-Host "[ERROR] icudtl.dat is missing from data directory" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path "$InstallDir\data\flutter_assets")) {
    Write-Host "[ERROR] flutter_assets is missing from data directory" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] All critical files verified" -ForegroundColor Green

# ============================================================================
# Step 5: Compile installer
# ============================================================================
Write-Host ""
Write-Host "[5/5] Compiling installer..."

# Clean old output directory
if (Test-Path $OutputDir) {
    Remove-Item $OutputDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

# Compile
$IssFile = Join-Path $ScriptDir "inno_setup_config.iss"
& $IsccPath $IssFile
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Installer compiled successfully!" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Installer compilation failed" -ForegroundColor Red
    exit 1
}

# Cleanup backup file
if (Test-Path $DartFfiBackup) {
    Remove-Item $DartFfiBackup -Force
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Build Complete!" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Installer location: $OutputDir"
Write-Host ""
$SetupExe = Join-Path $OutputDir "PonyNotesSetup.exe"
if (Test-Path $SetupExe) {
    $size = (Get-Item $SetupExe).Length
    Write-Host "[OK] Installer: $SetupExe" -ForegroundColor Green
    Write-Host "Size: $([math]::Round($size / 1MB, 2)) MB"
}
Write-Host ""
