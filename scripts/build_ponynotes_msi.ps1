param(
  [string]$ProjectRoot = "G:\pony\PonyNotes-New\frontend\appflowy_flutter",
  [string]$WixBin = "G:\pony\.tools\WixSharp.wix.bin\tools\bin",
  [string]$OutputDir = "G:\pony\PonyNotes-New\dist\installers",
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

$candle = Join-Path $WixBin "candle.exe"
$light = Join-Path $WixBin "light.exe"
if (!(Test-Path -LiteralPath $candle) -or !(Test-Path -LiteralPath $light)) {
  throw "WiX candle.exe/light.exe not found under $WixBin"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$workDir = Join-Path $OutputDir "_wix"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$wxsPath = Join-Path $workDir "PonyNotes.wxs"
$wixObjPath = Join-Path $workDir "PonyNotes.wixobj"
$msiPath = Join-Path $OutputDir "PonyNotes-$Version-x64.msi"

$excludedExtensions = @(".exp", ".lib", ".pdb", ".ilk", ".obj", ".map")
$excludedDirectoryNames = @("PonyNotes.exe.WebView2")
$files = Get-ChildItem -LiteralPath $releaseDir -Recurse -File |
  Where-Object {
    $relativePath = $_.FullName.Substring($releaseDir.Length).TrimStart(
      [System.IO.Path]::DirectorySeparatorChar,
      [System.IO.Path]::AltDirectorySeparatorChar
    )
    $pathParts = $relativePath.Split([System.IO.Path]::DirectorySeparatorChar)
    $excludedExtensions -notcontains $_.Extension.ToLowerInvariant() -and
    !($pathParts | Where-Object { $excludedDirectoryNames -contains $_ })
  } |
  Sort-Object FullName

if ($files.Count -eq 0) {
  throw "No files found to package in $releaseDir"
}

$blockedFiles = $files | Where-Object {
  $_.Extension.ToLowerInvariant() -eq ".map" -or
  $_.FullName -like "*\PonyNotes.exe.WebView2\*"
}
if ($blockedFiles.Count -gt 0) {
  throw "Package contains excluded files: $($blockedFiles[0].FullName)"
}

$whiteboardAssetFiles = $files | Where-Object {
  $_.FullName -like "*\data\flutter_assets\assets\excalidraw\*"
}
$whiteboardAssetSizeMb = [math]::Round(
  (($whiteboardAssetFiles | Measure-Object Length -Sum).Sum / 1MB),
  2
)
Write-Host "Packaging $($files.Count) files. Whiteboard assets: $($whiteboardAssetFiles.Count) files, ${whiteboardAssetSizeMb}MB"

$dirIdByPath = @{}
$dirXmlByParent = @{}
$components = New-Object System.Collections.Generic.List[string]
$componentRefs = New-Object System.Collections.Generic.List[string]
$dirCounter = 0
$fileCounter = 0

function Convert-ToXmlAttribute([string]$value) {
  return [System.Security.SecurityElement]::Escape($value)
}

function New-WixId([string]$prefix) {
  $script:dirCounter += 1
  return "{0}{1:D5}" -f $prefix, $script:dirCounter
}

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

function Get-DirectoryId([string]$relativeDir) {
  if ([string]::IsNullOrWhiteSpace($relativeDir) -or $relativeDir -eq ".") {
    return "INSTALLFOLDER"
  }

  if ($dirIdByPath.ContainsKey($relativeDir)) {
    return $dirIdByPath[$relativeDir]
  }

  $parentRel = Split-Path -Path $relativeDir -Parent
  $name = Split-Path -Path $relativeDir -Leaf
  if ([string]::IsNullOrWhiteSpace($parentRel)) {
    $parentRel = "."
  }

  $parentId = Get-DirectoryId $parentRel
  $dirId = New-WixId "DIR"
  $dirIdByPath[$relativeDir] = $dirId

  if (!$dirXmlByParent.ContainsKey($parentId)) {
    $dirXmlByParent[$parentId] = New-Object System.Collections.Generic.List[string]
  }
  $escapedName = Convert-ToXmlAttribute $name
  $dirXmlByParent[$parentId].Add("        <Directory Id=`"$dirId`" Name=`"$escapedName`" />")

  return $dirId
}

foreach ($file in $files) {
  $relativePath = Get-RelativePath $releaseDir $file.FullName
  $relativeDir = Split-Path -Path $relativePath -Parent
  if ([string]::IsNullOrWhiteSpace($relativeDir)) {
    $relativeDir = "."
  }

  $dirId = Get-DirectoryId $relativeDir
  $fileCounter += 1
  $componentId = "CMP{0:D5}" -f $fileCounter
  $fileId = "FIL{0:D5}" -f $fileCounter
  $source = Convert-ToXmlAttribute $file.FullName
  $name = Convert-ToXmlAttribute $file.Name
  $guid = [guid]::NewGuid().ToString("B").ToUpperInvariant()

  $components.Add(@"
    <DirectoryRef Id="$dirId">
      <Component Id="$componentId" Guid="$guid" Win64="yes">
        <File Id="$fileId" Name="$name" Source="$source" KeyPath="yes" />
      </Component>
    </DirectoryRef>
"@)
  $componentRefs.Add("      <ComponentRef Id=`"$componentId`" />")
}

function Write-DirectoryTree([string]$parentId, [int]$indent) {
  if (!$dirXmlByParent.ContainsKey($parentId)) {
    return @()
  }

  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($line in $dirXmlByParent[$parentId]) {
    if ($line -match 'Id="([^"]+)" Name="([^"]+)"') {
      $id = $Matches[1]
      $name = $Matches[2]
      $pad = " " * $indent
      $children = Write-DirectoryTree $id ($indent + 2)
      if ($children.Count -gt 0) {
        $lines.Add("$pad<Directory Id=`"$id`" Name=`"$name`">")
        foreach ($child in $children) {
          $lines.Add($child)
        }
        $lines.Add("$pad</Directory>")
      } else {
        $lines.Add("$pad<Directory Id=`"$id`" Name=`"$name`" />")
      }
    }
  }
  return $lines
}

$directoryTree = Write-DirectoryTree "INSTALLFOLDER" 10
$componentRefsText = ($componentRefs -join "`r`n")
$componentsText = ($components -join "`r`n")
$directoryTreeText = ($directoryTree -join "`r`n")

$upgradeCode = "{8FB60758-3C8A-48D1-BF9B-BA45111272ED}"
$shortcutGuid = "{7E04BD95-23A0-4D09-A06A-4B874D789497}"

$wxs = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="PonyNotes" Language="1033" Version="$Version" Manufacturer="PonyNotes" UpgradeCode="$upgradeCode">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" Platform="x64" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of PonyNotes is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="PonyNotes">
$directoryTreeText
        </Directory>
      </Directory>
      <Directory Id="ProgramMenuFolder">
        <Directory Id="ApplicationProgramsFolder" Name="PonyNotes" />
      </Directory>
    </Directory>

    <DirectoryRef Id="ApplicationProgramsFolder">
      <Component Id="ApplicationShortcut" Guid="$shortcutGuid" Win64="yes">
        <Shortcut Id="ApplicationStartMenuShortcut" Name="PonyNotes" Description="PonyNotes" Target="[INSTALLFOLDER]PonyNotes.exe" WorkingDirectory="INSTALLFOLDER" />
        <RemoveFolder Id="RemoveApplicationProgramsFolder" On="uninstall" />
        <RegistryValue Root="HKCU" Key="Software\PonyNotes\PonyNotes" Name="installed" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </DirectoryRef>

    <Feature Id="DefaultFeature" Title="PonyNotes" Level="1">
$componentRefsText
      <ComponentRef Id="ApplicationShortcut" />
    </Feature>
  </Product>

  <Fragment>
$componentsText
  </Fragment>
</Wix>
"@

Set-Content -LiteralPath $wxsPath -Value $wxs -Encoding UTF8

& $candle -nologo -arch x64 -out $wixObjPath $wxsPath
& $light -nologo -out $msiPath $wixObjPath

Get-Item -LiteralPath $msiPath
