param(
  [string]$ProjectRoot = "G:\pony\PonyNotes-New\frontend\appflowy_flutter",
  [string]$WixBin = "G:\pony\.tools\WixSharp.wix.bin\tools\bin",
  [string]$OutputDir = "G:\pony\PonyNotes-New\dist\installers",
  [string]$Version = "1.0.0",
  [string]$ArtifactSuffix = "",
  [string[]]$FlutterBuildArgs = @(),
  [switch]$EnableDiagnosticAutoExport,
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$releaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$shouldEnableDiagnosticAutoExport =
  $EnableDiagnosticAutoExport -or
  ($ArtifactSuffix -match '(?i)diagnostic')

if ($shouldEnableDiagnosticAutoExport) {
  if (-not ($FlutterBuildArgs | Where-Object { $_ -like '--dart-define=PONYNOTES_AUTO_EXPORT_DEBUG_LOGS=*' })) {
    $FlutterBuildArgs += '--dart-define=PONYNOTES_AUTO_EXPORT_DEBUG_LOGS=true'
  }

  if (-not ($FlutterBuildArgs | Where-Object { $_ -like '--dart-define=PONYNOTES_DIAGNOSTIC_BUILD_LABEL=*' })) {
    $diagnosticLabel = if ([string]::IsNullOrWhiteSpace($ArtifactSuffix)) {
      "diagnostic-$Version"
    } else {
      $ArtifactSuffix
    }
    $FlutterBuildArgs += "--dart-define=PONYNOTES_DIAGNOSTIC_BUILD_LABEL=$diagnosticLabel"
  }
}

if (!$SkipBuild) {
  Push-Location $ProjectRoot
  try {
    $buildArguments = @('build', 'windows', '--release')
    if ($FlutterBuildArgs.Count -gt 0) {
      $buildArguments += $FlutterBuildArgs
    }
    & flutter clean
    & flutter pub get
    & flutter @buildArguments
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
$wixToolsRoot = Split-Path -Path $WixBin -Parent
$wixZhCnLocalizationPath = Join-Path $wixToolsRoot "sdk\wixui\WixUI_zh-CN.wxl"
if (!(Test-Path -LiteralPath $wixZhCnLocalizationPath)) {
  throw "WiX zh-CN localization file not found: $wixZhCnLocalizationPath"
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$workDir = Join-Path $OutputDir "_wix"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$wxsPath = Join-Path $workDir "PonyNotes.wxs"
$wixObjPath = Join-Path $workDir "PonyNotes.wixobj"
$artifactVersion = if ([string]::IsNullOrWhiteSpace($ArtifactSuffix)) {
  $Version
} else {
  "$Version-$ArtifactSuffix"
}
$msiPath = Join-Path $OutputDir "PonyNotes-$artifactVersion-x64.msi"
$licensePath = Join-Path $workDir "License.rtf"
$installFolderName = "PonyNotes-$artifactVersion"

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
$ponyNotesExeFileId = "PonyNotesExeFile"

function Convert-ToXmlAttribute([string]$value) {
  return [System.Security.SecurityElement]::Escape($value)
}

function Convert-ToRtfText([string]$value) {
  $builder = New-Object System.Text.StringBuilder
  foreach ($char in $value.ToCharArray()) {
    $code = [int][char]$char
    if ($char -eq '\') {
      [void]$builder.Append('\\')
    } elseif ($char -eq '{') {
      [void]$builder.Append('\{')
    } elseif ($char -eq '}') {
      [void]$builder.Append('\}')
    } elseif ($code -eq 10) {
      [void]$builder.Append('\par ')
    } elseif ($code -eq 13) {
      continue
    } elseif ($code -gt 127) {
      $signedCode = $code
      if ($signedCode -gt 32767) {
        $signedCode -= 65536
      }
      [void]$builder.Append("\u$signedCode?")
    } else {
      [void]$builder.Append($char)
    }
  }
  return $builder.ToString()
}

function ConvertFrom-UnicodeEscapes([string]$value) {
  return [regex]::Replace($value, '\\u([0-9A-Fa-f]{4})', {
    param($match)
    return [string][char][Convert]::ToInt32($match.Groups[1].Value, 16)
  })
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
  if ($relativePath -eq "PonyNotes.exe") {
    $fileId = $ponyNotesExeFileId
  } else {
    $fileId = "FIL{0:D5}" -f $fileCounter
  }
  $source = Convert-ToXmlAttribute $file.FullName
  $name = Convert-ToXmlAttribute $file.Name
  $guid = [guid]::NewGuid().ToString("B").ToUpperInvariant()

  $components.Add(@"
    <DirectoryRef Id="$dirId">
      <Component Id="$componentId" Guid="$guid" Win64="yes">
        <File Id="$fileId" Name="$name" Source="$source" />
        <RegistryValue Root="HKCU" Key="Software\PonyNotes\PonyNotes\InstalledFiles" Name="$componentId" Type="integer" Value="1" KeyPath="yes" />
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

$cleanupCounter = 0
$directoryIdsToRemove = @("INSTALLFOLDER", "PONYROOTFOLDER") + ($dirIdByPath.Values | Sort-Object)
foreach ($dirIdToRemove in $directoryIdsToRemove) {
  $cleanupCounter += 1
  $cleanupComponentId = "DCL{0:D5}" -f $cleanupCounter
  $removeFolderId = "RMF{0:D5}" -f $cleanupCounter
  $cleanupGuid = [guid]::NewGuid().ToString("B").ToUpperInvariant()
  $registryName = Convert-ToXmlAttribute $dirIdToRemove

  $components.Add(@"
    <DirectoryRef Id="$dirIdToRemove">
      <Component Id="$cleanupComponentId" Guid="$cleanupGuid" Win64="yes">
        <RemoveFolder Id="$removeFolderId" On="uninstall" />
        <RegistryValue Root="HKCU" Key="Software\PonyNotes\PonyNotes\Directories" Name="$registryName" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </DirectoryRef>
"@)
  $componentRefs.Add("      <ComponentRef Id=`"$cleanupComponentId`" />")
}

$componentRefsText = ($componentRefs -join "`r`n")
$componentsText = ($components -join "`r`n")
$directoryTreeText = ($directoryTree -join "`r`n")

$upgradeCode = "{8FB60758-3C8A-48D1-BF9B-BA45111272ED}"
$shortcutGuid = "{7E04BD95-23A0-4D09-A06A-4B874D789497}"
$desktopShortcutGuid = "{E5886CC8-F134-401D-A3C1-64C72290E6DA}"
$escapedLicensePath = Convert-ToXmlAttribute $licensePath
$escapedInstallFolderName = Convert-ToXmlAttribute $installFolderName
$newerVersionMessage = Convert-ToXmlAttribute (ConvertFrom-UnicodeEscapes "\u5DF2\u5B89\u88C5\u66F4\u65B0\u7248\u672C\u7684 PonyNotes\u3002")
$launchCheckboxText = Convert-ToXmlAttribute (ConvertFrom-UnicodeEscapes "\u542F\u52A8 PonyNotes")
$licenseTemplate = ConvertFrom-UnicodeEscapes "PonyNotes \u5B89\u88C5\u7A0B\u5E8F`r`n`r`n\u672C\u5B89\u88C5\u5305\u4F1A\u5B89\u88C5 PonyNotes\u3002\u8BF7\u9009\u62E9\u5B89\u88C5\u7236\u76EE\u5F55\uFF0C\u5B89\u88C5\u5668\u4F1A\u81EA\u52A8\u521B\u5EFA {0} \u5B50\u6587\u4EF6\u5939\u3002"
$licenseText = $licenseTemplate -f $installFolderName
$licenseRtfText = Convert-ToRtfText $licenseText
$licenseRtf = '{\rtf1\ansi\deff0{\fonttbl{\f0 Microsoft YaHei;}}\fs20 ' + $licenseRtfText + '\par}'
Set-Content -LiteralPath $licensePath -Value $licenseRtf -Encoding ASCII

$wxs = @"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="PonyNotes" Language="2052" Version="$Version" Manufacturer="PonyNotes" UpgradeCode="$upgradeCode">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perUser" InstallPrivileges="limited" Platform="x64" />
    <MajorUpgrade DowngradeErrorMessage="$newerVersionMessage" />
    <MediaTemplate EmbedCab="yes" />
    <Property Id="WIXUI_INSTALLDIR" Value="PONYROOTFOLDER" />
    <Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOX" Value="1" />
    <Property Id="WIXUI_EXITDIALOGOPTIONALCHECKBOXTEXT" Value="$launchCheckboxText" />
    <Property Id="WixShellExecTarget" Value="[#$ponyNotesExeFileId]" />
    <CustomAction Id="LaunchPonyNotes" BinaryKey="WixCA" DllEntry="WixShellExec" Execute="immediate" Impersonate="yes" Return="ignore" />
    <WixVariable Id="WixUILicenseRtf" Value="$escapedLicensePath" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="LocalAppDataFolder">
        <Directory Id="PONYROOTFOLDER" Name="PonyNotes">
          <Directory Id="INSTALLFOLDER" Name="$escapedInstallFolderName">
$directoryTreeText
          </Directory>
        </Directory>
      </Directory>
      <Directory Id="ProgramMenuFolder">
        <Directory Id="ApplicationProgramsFolder" Name="PonyNotes" />
      </Directory>
      <Directory Id="DesktopFolder" Name="Desktop" />
    </Directory>

    <DirectoryRef Id="ApplicationProgramsFolder">
      <Component Id="ApplicationShortcut" Guid="$shortcutGuid" Win64="yes">
        <Shortcut Id="ApplicationStartMenuShortcut" Name="PonyNotes" Description="PonyNotes" Target="[INSTALLFOLDER]PonyNotes.exe" WorkingDirectory="INSTALLFOLDER" />
        <RemoveFolder Id="RemoveApplicationProgramsFolder" On="uninstall" />
        <RegistryValue Root="HKCU" Key="Software\PonyNotes\PonyNotes" Name="installed" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </DirectoryRef>

    <DirectoryRef Id="DesktopFolder">
      <Component Id="DesktopShortcut" Guid="$desktopShortcutGuid" Win64="yes">
        <Shortcut Id="ApplicationDesktopShortcut" Name="PonyNotes" Description="PonyNotes" Target="[INSTALLFOLDER]PonyNotes.exe" WorkingDirectory="INSTALLFOLDER" />
        <RegistryValue Root="HKCU" Key="Software\PonyNotes\PonyNotes" Name="desktopShortcut" Type="integer" Value="1" KeyPath="yes" />
      </Component>
    </DirectoryRef>

    <UI>
      <UIRef Id="WixUI_InstallDir" />
      <UIRef Id="WixUI_ErrorProgressText" />
      <Publish Dialog="ExitDialog" Control="Finish" Event="DoAction" Value="LaunchPonyNotes">WIXUI_EXITDIALOGOPTIONALCHECKBOX = 1 AND NOT Installed</Publish>
    </UI>

    <Feature Id="DefaultFeature" Title="PonyNotes" Level="1">
$componentRefsText
      <ComponentRef Id="ApplicationShortcut" />
      <ComponentRef Id="DesktopShortcut" />
    </Feature>
  </Product>

  <Fragment>
$componentsText
  </Fragment>
</Wix>
"@

Set-Content -LiteralPath $wxsPath -Value $wxs -Encoding UTF8

Remove-Item -LiteralPath $wixObjPath, $msiPath -ErrorAction SilentlyContinue

& $candle -nologo -arch x64 -ext WixUIExtension -ext WixUtilExtension -out $wixObjPath $wxsPath
if ($LASTEXITCODE -ne 0) {
  throw "WiX candle failed with exit code $LASTEXITCODE"
}

& $light -nologo -cultures:zh-CN -loc $wixZhCnLocalizationPath -ext WixUIExtension -ext WixUtilExtension -out $msiPath $wixObjPath
if ($LASTEXITCODE -ne 0) {
  throw "WiX light failed with exit code $LASTEXITCODE"
}

Get-Item -LiteralPath $msiPath
