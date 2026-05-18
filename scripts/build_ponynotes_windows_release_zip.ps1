param(
  [string]$ProjectRoot = "G:\pony\PonyNotes-New\frontend\appflowy_flutter",
  [string]$OutputDir = "G:\pony\PonyNotes-New\dist",
  [string]$Version = "1.0.0",
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$releaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"

if (!$SkipBuild) {
  Push-Location $ProjectRoot
  try {
    & flutter clean
    & flutter pub get
    & flutter build windows --release
  } finally {
    Pop-Location
  }
}

$exePath = Join-Path $releaseDir "PonyNotes.exe"
if (!(Test-Path -LiteralPath $exePath)) {
  throw "Release executable not found: $exePath"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$packageName = "PonyNotes-Windows-Release-$Version"
$stagingDir = Join-Path $OutputDir $packageName
$zipPath = Join-Path $OutputDir "$packageName.zip"

if (Test-Path -LiteralPath $stagingDir) {
  Remove-Item -LiteralPath $stagingDir -Recurse -Force
}
if (Test-Path -LiteralPath $zipPath) {
  Remove-Item -LiteralPath $zipPath -Force
}

$excludedExtensions = @(".exp", ".lib", ".pdb", ".ilk", ".obj", ".map")
$excludedDirectoryNames = @(
  "PonyNotes.exe.WebView2",
  "Cache",
  "Code Cache",
  "GPUCache",
  "ShaderCache",
  "Service Worker"
)

function Get-RelativePath([string]$basePath, [string]$targetPath) {
  $baseFullPath = [System.IO.Path]::GetFullPath($basePath)
  if (!$baseFullPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $baseFullPath += [System.IO.Path]::DirectorySeparatorChar
  }
  $baseUri = New-Object System.Uri($baseFullPath)
  $targetUri = New-Object System.Uri([System.IO.Path]::GetFullPath($targetPath))
  return [System.Uri]::UnescapeDataString(
    $baseUri.MakeRelativeUri($targetUri).ToString()
  ).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Test-IsExcludedFile([System.IO.FileInfo]$file) {
  if ($excludedExtensions -contains $file.Extension.ToLowerInvariant()) {
    return $true
  }

  $relativePath = Get-RelativePath $releaseDir $file.FullName
  $pathParts = $relativePath.Split([System.IO.Path]::DirectorySeparatorChar)
  return [bool]($pathParts | Where-Object { $excludedDirectoryNames -contains $_ })
}

$files = Get-ChildItem -LiteralPath $releaseDir -Recurse -File |
  Where-Object { !(Test-IsExcludedFile $_) } |
  Sort-Object FullName

if ($files.Count -eq 0) {
  throw "No files found to package in $releaseDir"
}

foreach ($file in $files) {
  $relativePath = Get-RelativePath $releaseDir $file.FullName
  $targetPath = Join-Path $stagingDir $relativePath
  $targetParent = Split-Path -Parent $targetPath
  New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
}

$blockedFiles = Get-ChildItem -LiteralPath $stagingDir -Recurse -File |
  Where-Object {
    $_.Extension.ToLowerInvariant() -eq ".map" -or
    $_.FullName -like "*\PonyNotes.exe.WebView2\*"
  }
if ($blockedFiles.Count -gt 0) {
  throw "Release package contains excluded files: $($blockedFiles[0].FullName)"
}

$whiteboardAssetFiles = Get-ChildItem -LiteralPath $stagingDir -Recurse -File |
  Where-Object { $_.FullName -like "*\data\flutter_assets\assets\excalidraw\*" }
$whiteboardAssetSizeMb = [math]::Round(
  (($whiteboardAssetFiles | Measure-Object Length -Sum).Sum / 1MB),
  2
)

Compress-Archive -Path (Join-Path $stagingDir "*") -DestinationPath $zipPath

$zipInfo = Get-Item -LiteralPath $zipPath
Write-Host "Packaged $($files.Count) files into $zipPath"
Write-Host "Whiteboard assets: $($whiteboardAssetFiles.Count) files, ${whiteboardAssetSizeMb}MB"
Write-Host "ZIP size: $([math]::Round($zipInfo.Length / 1MB, 2))MB"

$zipInfo
