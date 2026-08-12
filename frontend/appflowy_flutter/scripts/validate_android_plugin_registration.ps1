param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$ArtifactPath = ''
)

$ErrorActionPreference = 'Stop'

function Fail {
  param([string]$Message)
  Write-Error $Message
  exit 1
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$mainActivityPath = Join-Path $root 'android/app/src/main/kotlin/com/xiaomabiji/app/note/MainActivity.kt'
$dependenciesPath = Join-Path $root '.flutter-plugins-dependencies'
$registrantPath = Join-Path $root 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
$proguardPath = Join-Path $root 'android/app/proguard-rules.pro'

if (-not (Test-Path -LiteralPath $mainActivityPath)) {
  Fail "Missing MainActivity.kt: $mainActivityPath"
}

$mainActivity = Get-Content -LiteralPath $mainActivityPath -Raw
if ($mainActivity -notmatch '(?m)^\s*super\.configureFlutterEngine\(flutterEngine\)\s*$') {
  Fail 'MainActivity must call super.configureFlutterEngine(flutterEngine) to keep Flutter automatic plugin registration.'
}

if ($mainActivity -match '(?m)flutterEngine(?:\.getPlugins\(\)|\.plugins)\.add\s*\(') {
  Fail 'MainActivity contains manual plugin registration. Keep plugin registration in Flutter GeneratedPluginRegistrant.java.'
}

if (-not (Test-Path -LiteralPath $dependenciesPath)) {
  Fail "Missing generated Flutter plugin dependency manifest: $dependenciesPath. Run flutter pub get first."
}

try {
  $dependencies = Get-Content -LiteralPath $dependenciesPath -Raw | ConvertFrom-Json
} catch {
  Fail "Unable to parse generated Flutter plugin dependency manifest: $($_.Exception.Message)"
}

$androidPlugins = @($dependencies.plugins.android)
if ($androidPlugins.Count -eq 0) {
  Fail 'The generated Flutter plugin dependency manifest contains no Android plugins.'
}

if (-not (Test-Path -LiteralPath $registrantPath)) {
  Fail "Missing GeneratedPluginRegistrant.java: $registrantPath. Run flutter pub get first."
}

if (-not (Test-Path -LiteralPath $proguardPath)) {
  Fail "Missing Android release keep rules: $proguardPath"
}

$registrant = Get-Content -LiteralPath $registrantPath -Raw
$proguard = Get-Content -LiteralPath $proguardPath -Raw
$pluginNames = @($androidPlugins | ForEach-Object { $_.name })

# These plugins are part of the QR login and the Android surface that previously
# exposed the manual-registration regression. FFI plugins such as pdfrx can appear
# in the Flutter dependency manifest without a Java registrar, so the source guard
# above remains the protection for all generated plugin types.
$requiredRegistrations = [ordered]@{
  'flutter_inappwebview_android' = 'com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin'
  'douyin_login' = 'com.postliu.douyin_login.DouyinPlugin'
  'fluwx' = 'com.jarvan.fluwx.FluwxPlugin'
  'device_info_plus' = 'dev.fluttercommunity.plus.device_info.DeviceInfoPlusPlugin'
  'image_picker_android' = 'io.flutter.plugins.imagepicker.ImagePickerPlugin'
  'permission_handler_android' = 'com.baseflow.permissionhandler.PermissionHandlerPlugin'
}

foreach ($required in $requiredRegistrations.GetEnumerator()) {
  if ($pluginNames -notcontains $required.Key) {
    Fail "Required Android plugin '$($required.Key)' is absent from .flutter-plugins-dependencies."
  }

  if (-not $registrant.Contains($required.Value)) {
    Fail "GeneratedPluginRegistrant.java is missing $($required.Key): $($required.Value)"
  }

  $keepPattern = '(?m)^\s*-keep\s+class\s+' + [regex]::Escape($required.Value) + '\s*\{'
  if ($proguard -notmatch $keepPattern) {
    Fail "Android release keep rules are missing $($required.Key): $($required.Value)"
  }
}

if (-not [string]::IsNullOrWhiteSpace($ArtifactPath)) {
  $artifact = if ([System.IO.Path]::IsPathRooted($ArtifactPath)) {
    $ArtifactPath
  } else {
    Join-Path $root $ArtifactPath
  }

  if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) {
    Fail "Expected Android release artifact was not produced: $artifact"
  }

  $artifactInfo = Get-Item -LiteralPath $artifact
  if ($artifactInfo.Length -le 0) {
    Fail "Android release artifact is empty: $artifact"
  }

  Write-Host "Android release artifact OK: $artifact ($($artifactInfo.Length) bytes)"
}

Write-Host "Android plugin registration OK: $($pluginNames.Count) generated Android plugins; QR login plugins are present."
