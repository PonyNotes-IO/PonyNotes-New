# PonyNotes Windows Installer Builder
# Compatible with PowerShell execution environment

# Stop on any unhandled error so silent failures don't slip through.
$ErrorActionPreference = "Stop"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

# Run an external command, capture stdout AND stderr (so we can show real
# errors on failure instead of swallowing them with 2>$null), and return its
# exit code. Stdout/stderr are also mirrored to the live console.
function Invoke-Step {
    param(
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string[]]$Args
    )

    $stdoutLog = [System.IO.Path]::GetTempFileName()
    $stderrLog = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $File -ArgumentList $Args `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError  $stderrLog

        $stdoutText = if (Test-Path $stdoutLog) { Get-Content $stdoutLog -Raw -Encoding UTF8 } else { "" }
        $stderrText = if (Test-Path $stderrLog) { Get-Content $stderrLog -Raw -Encoding UTF8 } else { "" }

        if ($stdoutText) { Write-Host $stdoutText.TrimEnd() }
        if ($stderrText) {
            foreach ($line in ($stderrText -split "`r?`n")) {
                if ($line.Trim().Length -gt 0) { Write-Host $line -ForegroundColor DarkYellow }
            }
        }
        return $proc.ExitCode
    } finally {
        Remove-Item $stdoutLog, $stderrLog -ErrorAction SilentlyContinue
    }
}

# Copy a single file. Fails (throws) if the source is missing.
function Copy-RequiredFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$DestinationDir
    )
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Required file not found: $Source"
    }
    $destFile = Join-Path $DestinationDir (Split-Path -Leaf $Source)
    Copy-Item -LiteralPath $Source -Destination $destFile -Force
}

# Copy a single file. Warns (does not throw) if the source is missing.
function Copy-OptionalFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$DestinationDir,
        [string]$Label = (Split-Path -Leaf $Source)
    )
    if (-not (Test-Path -LiteralPath $Source)) {
        Write-Host "  [WARN] Skipping $Label (source not found: $Source)" -ForegroundColor Yellow
        return $false
    }
    $destFile = Join-Path $DestinationDir (Split-Path -Leaf $Source)
    Copy-Item -LiteralPath $Source -Destination $destFile -Force
    return $true
}

# Copy all DLLs in a directory (non-recursive). Warns if dir is missing.
function Copy-OptionalDlls {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$DestinationDir,
        [string]$Label = $SourceDir
    )
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        Write-Host "  [WARN] Skipping $Label (directory not found)" -ForegroundColor Yellow
        return 0
    }
    $files = Get-ChildItem -LiteralPath $SourceDir -Filter "*.dll" -File -ErrorAction Stop
    if (-not $files) {
        Write-Host "  [WARN] No DLLs found in $SourceDir" -ForegroundColor Yellow
        return 0
    }
    foreach ($f in $files) {
        Copy-Item -LiteralPath $f.FullName -Destination $DestinationDir -Force
    }
    return $files.Count
}

# Copy a directory tree using robocopy (most reliable on Windows for bulk
# directory copies; PowerShell's Copy-Item has known quirks with wildcard
# source paths on already-existing destinations). Warns if source is missing.
#
# IMPORTANT: we run robocopy via Start-Process -Wait -PassThru so we get a
# proper ExitCode property. When invoked as `$rc = robocopy ...` directly,
# PowerShell assigns the (empty) stdout to $rc and discards the actual
# return code in $LASTEXITCODE, which silently disables any error checking.
#
# IMPORTANT: this function CLEARS the destination before copying (it removes
# the existing tree then asks robocopy to mirror the source). This is the
# right semantic for sub-directories like data/ or webview2_fixed/ where
# stale leftovers would be wrong, but it is WRONG when the destination is
# $InstallDir itself - the caller would silently lose every other file just
# copied. Pass -ClearDestination:$false when copying into the installer
# root so robocopy overlays without removing siblings.
function Copy-OptionalDir {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$DestinationDir,
        [string]$Label = $SourceDir,
        [bool]$ClearDestination = $true
    )
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        Write-Host "  [WARN] Skipping $Label (directory not found)" -ForegroundColor Yellow
        return $false
    }
    if ($ClearDestination -and (Test-Path -LiteralPath $DestinationDir)) {
        Remove-Item -LiteralPath $DestinationDir -Recurse -Force
    } elseif (-not (Test-Path -LiteralPath $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }
    # robocopy exit codes: 0=no change, 1=files copied, 2=extra files deleted,
    # 3=both. Anything >=8 is an error we care about.
    $args = @("`"$SourceDir`"", "`"$DestinationDir`"", "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/R:0", "/W:0")
    $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ge 8) {
        throw "robocopy failed (exit code $($proc.ExitCode)) copying '$SourceDir' -> '$DestinationDir'"
    }
    return $true
}

# Copy the *contents* of $SourceDir into an already-existing $DestinationDir,
# preserving subdirectories. Used for the Flutter Release root -> InstallerDir
# bulk copy. Throws (rather than warns) on missing source because Release is
# the build artifact this installer is built around.
function Copy-DirContents {
    param(
        [Parameter(Mandatory)][string]$SourceDir,
        [Parameter(Mandatory)][string]$DestinationDir,
        [string]$Label = $SourceDir
    )
    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "Required source directory not found: $SourceDir ($Label)"
    }
    if (-not (Test-Path -LiteralPath $DestinationDir)) {
        New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
    }
    # robocopy with a bare source path copies the contents of SourceDir into
    # DestinationDir (this is the conventional, reliable Windows bulk copy;
    # PowerShell's Copy-Item has known quirks with wildcard source paths on
    # already-existing destinations, which is why we don't use it here).
    $args = @("`"$SourceDir`"", "`"$DestinationDir`"", "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/R:0", "/W:0")
    $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ge 8) {
        throw "robocopy failed (exit code $($proc.ExitCode)) copying contents of '$SourceDir' -> '$DestinationDir'"
    }
}

# Verify a list of required paths (file or directory). Throws on first miss.
function Assert-AllExist {
    param(
        [Parameter(Mandatory)][string[]]$Paths,
        [string]$Context = "Verification"
    )
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p)) {
            throw "$Context failed: missing '$p'"
        }
    }
}

# ----------------------------------------------------------------------------
# Resolve paths
# ----------------------------------------------------------------------------

Write-Host "============================================="
Write-Host "  PonyNotes Windows Installer Builder"
Write-Host "============================================="
Write-Host ""

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$FrontendDir = Join-Path $ScriptDir "..\.."
$RustLibDir  = Join-Path $FrontendDir "rust-lib"
$FlutterDir  = Join-Path $FrontendDir "appflowy_flutter"
$InstallDir  = Join-Path $ScriptDir "AppFlowy"
$OutputDir   = Join-Path $ScriptDir "Output"

$Version = "0.9.9"

# Detect Inno Setup compiler
$IsccPath = "D:\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $IsccPath)) {
    $iscc = Get-Command iscc -ErrorAction SilentlyContinue
    if ($iscc) { $IsccPath = $iscc.Source }
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

try {
    Write-Host "Getting dependencies..."
    $pubCode = Invoke-Step -File "flutter" -Args @("pub", "get")
    Write-Host "Done getting dependencies (exit code: $pubCode)"
    if ($pubCode -ne 0) {
        throw "flutter pub get failed with exit code $pubCode"
    }

    Write-Host "Building Flutter Windows Release..."
    Write-Host "Starting build at $(Get-Date -Format 'HH:mm:ss')"
    $buildCode = Invoke-Step -File "flutter" -Args @("build", "windows", "--release")
    Write-Host "Build command finished with code: $buildCode"
    if ($buildCode -ne 0) {
        throw "flutter build windows --release failed with exit code $buildCode"
    }
} finally {
    Pop-Location
}

$releaseDir = Join-Path $FlutterDir "build\windows\x64\runner\Release"
$exePath    = Join-Path $releaseDir  "PonyNotes.exe"
$dataDir    = Join-Path $releaseDir  "data"

# Strong pre-flight check: Flutter build is only "successful" if the runtime
# files that the engine needs to start are actually present. This is the
# root-cause check that prevents shipping a broken installer.
Assert-AllExist -Context "Flutter build output" -Paths @(
    $exePath,
    (Join-Path $releaseDir "flutter_windows.dll"),
    (Join-Path $dataDir "app.so"),
    (Join-Path $dataDir "icudtl.dat"),
    (Join-Path $dataDir "flutter_assets")
)
Write-Host "[OK] Flutter Release build verified (exe + engine + AOT snapshot + assets)"

# ============================================================================
# Step 2: Prepare installation directory
# ============================================================================
Write-Host ""
Write-Host "[2/3] Preparing installation directory..."

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Copy Flutter build root (exe + flutter_windows.dll + icudtl.dat etc.).
# Use robocopy here instead of PowerShell Copy-Item: Copy-Item with a wildcard
# source path on an existing destination silently drops files on some Windows
# configurations, which was the root cause of the original silent-failure bug.
Write-Host "Copying Flutter build files..."
Copy-DirContents -SourceDir $releaseDir -DestinationDir $InstallDir -Label "Flutter Release dir"

# Ensure the data/ subtree is present and contains the runtime files.
Write-Host "Copying data directory..."
Copy-OptionalDir -SourceDir $dataDir -DestinationDir (Join-Path $InstallDir "data") -Label "Flutter data dir"

# Critical: data\app.so / icudtl.dat / flutter_assets MUST exist after copy.
Assert-AllExist -Context "Installation data dir" -Paths @(
    (Join-Path $InstallDir "data\app.so"),
    (Join-Path $InstallDir "data\icudtl.dat"),
    (Join-Path $InstallDir "data\flutter_assets")
)
Write-Host "[OK] Critical AOT/ICU/assets files verified"

# Strip legacy AppFlowy artifacts that may have been copied verbatim.
foreach ($legacy in @("AppFlowy.exe", "AppFlowy.exp", "AppFlowy.lib")) {
    $p = Join-Path $InstallDir $legacy
    if (Test-Path $p) {
        Remove-Item $p -Force
        Write-Host "  [CLEAN] Removed legacy $legacy"
    }
}

# Flutter plugin DLLs. Fail if there are zero - that almost always means the
# build was incomplete or plugins were never generated.
Write-Host "Copying Flutter plugin DLLs..."
$pluginsRoot = Join-Path $FlutterDir "build\windows\x64\plugins"
if (-not (Test-Path $pluginsRoot)) {
    throw "Flutter plugins directory not found: $pluginsRoot"
}
$pluginDlls = @(Get-ChildItem -Path (Join-Path $pluginsRoot "*\Release\*.dll") -File -ErrorAction SilentlyContinue)
if ($pluginDlls.Count -eq 0) {
    throw "No Flutter plugin DLLs found under $pluginsRoot\*\Release"
}
foreach ($dll in $pluginDlls) {
    Copy-Item -LiteralPath $dll.FullName -Destination $InstallDir -Force
}
Write-Host "  [OK] Copied $($pluginDlls.Count) plugin DLL(s)"

# ANGLE DLLs (optional - some Flutter versions ship them, others don't).
Write-Host "Copying ANGLE DLLs..."
$angleDir = Join-Path $FlutterDir "build\windows\x64\ANGLE"
$angleCount = Copy-OptionalDlls -SourceDir $angleDir -DestinationDir $InstallDir -Label "ANGLE"
if ($angleCount -gt 0) { Write-Host "  [OK] Copied $angleCount ANGLE DLL(s)" }

# libmpv (optional - only present when media_kit is enabled). The libmpv
# directory contains loose files that should be merged into the installer
# root WITHOUT clearing the rest of the installer (otherwise we'd nuke the
# PonyNotes.exe etc. we already copied above).
Write-Host "Copying libmpv DLL..."
$mpvDir = Join-Path $FlutterDir "build\windows\x64\libmpv"
if (Copy-OptionalDir -SourceDir $mpvDir -DestinationDir $InstallDir -Label "libmpv" -ClearDestination:$false) {
    Write-Host "  [OK] libmpv bundled"
}

# pdfium (optional - only present when pdf rendering is enabled).
Write-Host "Copying pdfium DLL..."
$pdfiumBase = Join-Path $FlutterDir "build\windows\x64\.lib\chromium"
if (Test-Path $pdfiumBase) {
    $pdfiumDlls = @(Get-ChildItem -Path (Join-Path $pdfiumBase "*\x64\pdfium.dll") -File -ErrorAction SilentlyContinue)
    foreach ($dll in $pdfiumDlls) {
        Copy-Item -LiteralPath $dll.FullName -Destination $InstallDir -Force
    }
    if ($pdfiumDlls.Count -gt 0) { Write-Host "  [OK] Copied $($pdfiumDlls.Count) pdfium DLL(s)" }
} else {
    Write-Host "  [WARN] pdfium base directory not found, skipping" -ForegroundColor Yellow
}

# dart_ffi.dll - optional but strongly expected.
Write-Host "Copying dart_ffi.dll..."
$dartFfiFromBuild = Join-Path $releaseDir "dart_ffi.dll"
$dartFfiFromSrc   = Join-Path $FlutterDir "windows\flutter\dart_ffi\dart_ffi.dll"
if (Test-Path $dartFfiFromBuild) {
    Copy-Item -LiteralPath $dartFfiFromBuild -Destination (Join-Path $InstallDir "dart_ffi.dll") -Force
    Write-Host "  [OK] dart_ffi.dll copied from Flutter build output"
} elseif (Test-Path $dartFfiFromSrc) {
    Copy-Item -LiteralPath $dartFfiFromSrc -Destination (Join-Path $InstallDir "dart_ffi.dll") -Force
    Write-Host "  [OK] dart_ffi.dll copied from source"
} else {
    Write-Host "  [WARN] dart_ffi.dll not found (will rely on Flutter SDK runtime)" -ForegroundColor Yellow
}

# Rust DLLs.
Write-Host "Copying Rust DLL dependencies..."
$rustDeps = Join-Path $RustLibDir "target\release\deps"
$rustDlls = Join-Path $RustLibDir "target\release"
$rustCount = 0
$rustCount += Copy-OptionalDlls -SourceDir $rustDeps -DestinationDir $InstallDir -Label "Rust deps"
$rustCount += Copy-OptionalDlls -SourceDir $rustDlls -DestinationDir $InstallDir -Label "Rust release"
Write-Host "  [OK] Copied $rustCount Rust DLL(s)"

# VC++ Redistributable (optional - bundled if present in scripts dir).
Write-Host "Copying VC++ Redistributable..."
$vcRedist = Join-Path $ScriptDir "vc_redist_x64.exe"
if (Test-Path $vcRedist) {
    Copy-Item -LiteralPath $vcRedist -Destination $InstallDir -Force
    Write-Host "  [OK] vc_redist_x64.exe bundled"
} else {
    Write-Host "  [WARN] vc_redist_x64.exe not found in scripts dir; target machines need VC++ runtime pre-installed" -ForegroundColor Yellow
}

# WebView2: rely on the Evergreen standalone installer that ships in the
# install directory.  At install time, Inno Setup's [Run] section silently
# installs it to the system (C:\Program Files (x86)\Microsoft\EdgeWebView\)
# so every target machine ends up with a consistent, auto-updating WebView2
# without us having to ship a frozen-in-time fixed-version directory that
# may or may not match the target OS.
Write-Host "Downloading WebView2 Evergreen installer..."
$webview2SetupUrl  = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
$webview2SetupPath = Join-Path $InstallDir "MicrosoftEdgeWebview2Setup.exe"
if (-not (Test-Path $webview2SetupPath)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $webview2SetupUrl -OutFile $webview2SetupPath -UseBasicParsing -TimeoutSec 120
        $setupSize = [math]::Round((Get-Item $webview2SetupPath).Length / 1MB, 2)
        Write-Host "  [OK] WebView2 installer downloaded: $setupSize MB"
    } catch {
        Write-Host "  [WARN] Failed to download WebView2 installer: $_" -ForegroundColor Yellow
        Write-Host "  Target machines will need WebView2 pre-installed." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [OK] WebView2 installer already present, skipping download"
}

# Final hard check on the installation payload before we hand it to Inno Setup.
Assert-AllExist -Context "Installation payload" -Paths @(
    (Join-Path $InstallDir "PonyNotes.exe"),
    (Join-Path $InstallDir "flutter_windows.dll"),
    (Join-Path $InstallDir "data\app.so"),
    (Join-Path $InstallDir "data\icudtl.dat"),
    (Join-Path $InstallDir "data\flutter_assets")
)
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
    throw "Inno Setup config not found: $issFile"
}

Write-Host "Running: $IsccPath $issFile"
$issCode = Invoke-Step -File $IsccPath -Args @($issFile)
if ($issCode -ne 0) {
    throw "Inno Setup compilation failed with exit code $issCode"
}
Write-Host "[OK] Installer compiled successfully!" -ForegroundColor Green

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