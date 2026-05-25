param(
    [string]$WorkspaceDir = ""
)

# Auto-detect workspace directory if not provided
if ([string]::IsNullOrWhiteSpace($WorkspaceDir)) {
    $WorkspaceDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
}

$ErrorActionPreference = "Stop"

$NDK = "D:\Android\android-sdk\ndk\26.1.10909125\toolchains\llvm\prebuilt\windows-x86_64\sysroot\usr\lib"

# Step 1: Copy arm64-v8a and x86_64 .so files into rust-lib/jniLibs/*
$Arm64Jni   = Join-Path $WorkspaceDir "rust-lib\jniLibs\arm64-v8a"
$Arm64Src   = Join-Path $WorkspaceDir "rust-lib\target\aarch64-linux-android\debug\libdart_ffi.so"
$Arm64Deps  = Join-Path $WorkspaceDir "rust-lib\target\aarch64-linux-android\debug\deps"
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

$X86Jni  = Join-Path $WorkspaceDir "rust-lib\jniLibs_x86_64\x86_64"
$X86Src  = Join-Path $WorkspaceDir "rust-lib\target\x86_64-linux-android\debug\libdart_ffi.so"
$X86Deps = Join-Path $WorkspaceDir "rust-lib\target\x86_64-linux-android\debug\deps"
$X86Cxx  = Join-Path $NDK "x86_64-linux-android\libc++_shared.so"

Write-Host "Copying x86_64 native libraries..."
if (!(Test-Path $X86Jni)) {
    New-Item -ItemType Directory -Path $X86Jni -Force | Out-Null
}
if (Test-Path $X86Src) {
    Copy-Item -Path $X86Src -Destination $X86Jni -Force
    Write-Host "  Copied libdart_ffi.so"
} else {
    Write-Host "  WARNING: $X86Src not found"
}
if (Test-Path $X86Deps) {
    Get-ChildItem "$X86Deps\*.so" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $X86Jni -Force
        Write-Host "  Copied $($_.Name)"
    }
}
if (Test-Path $X86Cxx) {
    Copy-Item -Path $X86Cxx -Destination $X86Jni -Force
    Write-Host "  Copied libc++_shared.so"
} else {
    Write-Host "  WARNING: $X86Cxx not found"
}
Write-Host "x86_64 copy complete."

# Step 2: Copy jniLibs/* and binding.h into the Flutter Android project
$Dest        = Join-Path $WorkspaceDir "appflowy_flutter\android\app\src\main"
$DestJni    = Join-Path $Dest "jniLibs"
$DestArm64  = Join-Path $DestJni "arm64-v8a"
$DestX86    = Join-Path $DestJni "x86_64"
$DestClasses = Join-Path $Dest "Classes"
$SrcBinding  = Join-Path $WorkspaceDir "rust-lib\dart-ffi\binding.h"

Write-Host "Copying into Flutter Android project..."
if (Test-Path $DestJni) {
    Remove-Item -Path $DestJni -Recurse -Force
}
New-Item -ItemType Directory -Path $DestArm64 -Force | Out-Null
New-Item -ItemType Directory -Path $DestX86 -Force | Out-Null

if (Test-Path $Arm64Jni) {
    Get-ChildItem $Arm64Jni -Filter "*.so" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DestArm64 -Force
        Write-Host "  Copied arm64-v8a/$($_.Name)"
    }
} else {
    Write-Host "  WARNING: $Arm64Jni not found, skipping arm64-v8a copy"
}

if (Test-Path $X86Jni) {
    Get-ChildItem $X86Jni -Filter "*.so" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $DestX86 -Force
        Write-Host "  Copied x86_64/$($_.Name)"
    }
} else {
    Write-Host "  WARNING: $X86Jni not found, skipping x86_64 copy"
}

if (Test-Path $SrcBinding) {
    New-Item -ItemType Directory -Path $DestClasses -Force | Out-Null
    Copy-Item -Path $SrcBinding -Destination $DestClasses -Force
    Write-Host "  Copied binding.h to Classes/"
} else {
    Write-Host "  WARNING: $SrcBinding not found, skipping binding.h copy"
}

Write-Host "AppFlowy-Core multi-arch copy done."
