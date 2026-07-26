param(
    [string]$WorkspaceDir = "",
    [ValidateSet("release", "debug")]
    [string]$Profile = "release"
)

# Auto-detect workspace directory if not provided
if ([string]::IsNullOrWhiteSpace($WorkspaceDir)) {
    $WorkspaceDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

$ErrorActionPreference = "Stop"

$NDK = "D:\Android\android-sdk\ndk\26.1.10909125\toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib"

# ---------------------------------------------------------------------------
# Step 1: Build Rust libs for Android (arm64-v8a only) with size-optimized flags.
# These flags are passed ONLY here via RUSTFLAGS, so desktop builds are not affected.
#   -C strip=symbols     : strip symbol/debug info from the produced .so
#   -C panic=abort       : remove unwinding tables (saves a few MB)
# ---------------------------------------------------------------------------
$RustFlags = "-C strip=symbols -C panic=abort"
$env:RUSTFLAGS = $RustFlags

Write-Host "Building Rust libs for Android (arm64-v8a, profile=$Profile)..."
Write-Host "  RUSTFLAGS = $RustFlags"

$BuildArgs = @(
    "build",
    "--profile", $Profile,
    "--target", "aarch64-linux-android",
    "-p", "dart-ffi"
)

Push-Location (Join-Path $WorkspaceDir "rust-lib")
try {
    & cargo @BuildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "cargo build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
# Step 2: Copy arm64-v8a .so files into rust-lib/jniLibs/arm64-v8a
# ---------------------------------------------------------------------------
$Arm64ProfileDir = if ($Profile -eq "release") { "release" } else { "debug" }
$Arm64Jni   = Join-Path $WorkspaceDir "rust-lib\jniLibs\arm64-v8a"
$Arm64Src   = Join-Path $WorkspaceDir "rust-lib\target\aarch64-linux-android\$Arm64ProfileDir\libdart_ffi.so"
$Arm64Deps  = Join-Path $WorkspaceDir "rust-lib\target\aarch64-linux-android\$Arm64ProfileDir\deps"
$Arm64Cxx   = Join-Path $NDK "aarch64-linux-android\libc++_shared.so"

Write-Host "Copying ARM64 (arm64-v8a) native libraries..."
if (!(Test-Path $Arm64Jni)) {
    New-Item -ItemType Directory -Path $Arm64Jni -Force | Out-Null
}
if (Test-Path $Arm64Src) {
    Copy-Item -Path $Arm64Src -Destination $Arm64Jni -Force
    Write-Host "  Copied libdart_ffi.so"
} else {
    Write-Host "  WARNING: $Arm64Src not found"
}
if (Test-Path $Arm64Deps) {
    Get-ChildItem "$Arm64Deps\*.so" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $Arm64Jni -Force
        Write-Host "  Copied $($_.Name)"
    }
}
if (Test-Path $Arm64Cxx) {
    Copy-Item -Path $Arm64Cxx -Destination $Arm64Jni -Force
    Write-Host "  Copied libc++_shared.so"
} else {
    Write-Host "  WARNING: $Arm64Cxx not found"
}
Write-Host "ARM64 copy complete."

# ---------------------------------------------------------------------------
# Step 3: Copy arm64-v8a + binding.h into the Flutter Android project.
# Only arm64-v8a is shipped for production (armeabi-v7a / x86_64 dropped).
# ---------------------------------------------------------------------------
$Dest        = Join-Path $WorkspaceDir "appflowy_flutter\android\app\src\main"
$DestJni     = Join-Path $Dest "jniLibs"
$DestArm64   = Join-Path $DestJni "arm64-v8a"
$DestClasses = Join-Path $Dest "Classes"
$SrcBinding  = Join-Path $WorkspaceDir "rust-lib\dart-ffi\binding.h"

Write-Host "Copying into Flutter Android project..."
if (Test-Path $DestJni) {
    Remove-Item -Path $DestJni -Recurse -Force
}
New-Item -ItemType Directory -Path $DestArm64 -Force | Out-Null

if (Test-Path $Arm64Jni) {
    Get-ChildItem $Arm64Jni -Filter "*.so" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DestArm64 -Force
        Write-Host "  Copied arm64-v8a/$($_.Name)"
    }
} else {
    Write-Host "  WARNING: $Arm64Jni not found, skipping arm64-v8a copy"
}

if (Test-Path $SrcBinding) {
    New-Item -ItemType Directory -Path $DestClasses -Force | Out-Null
    Copy-Item -Path $SrcBinding -Destination $DestClasses -Force
    Write-Host "  Copied binding.h to Classes/"
} else {
    Write-Host "  WARNING: $SrcBinding not found, skipping binding.h copy"
}

Write-Host "AppFlowy-Core arm64-v8a copy done."
