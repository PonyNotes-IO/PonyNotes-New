param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Fail {
  param([string]$Message)
  Write-Error $Message
  exit 1
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$envPath = Join-Path $root '.env'
$generatedPath = Join-Path $root 'lib\env\env.g.dart'

if (-not (Test-Path -LiteralPath $envPath)) {
  Fail "Missing .env in Flutter project root: $envPath"
}

$envContent = Get-Content -LiteralPath $envPath -Raw

function Get-DotEnvValue {
  param([string]$Name)

  $escapedName = [regex]::Escape($Name)
  $match = [regex]::Match($envContent, "(?m)^\s*$escapedName\s*=\s*(.*?)\s*$")
  if (-not $match.Success) {
    Fail "Missing required .env key: $Name"
  }

  return $match.Groups[1].Value.Trim().Trim('"').Trim("'")
}

$cloudUrl = Get-DotEnvValue 'APPFLOWY_CLOUD_URL'
$authenticatorType = Get-DotEnvValue 'AUTHENTICATOR_TYPE'
$baseWebDomain = Get-DotEnvValue 'BASE_WEB_DOMAIN'

if ([string]::IsNullOrWhiteSpace($cloudUrl)) {
  Fail "APPFLOWY_CLOUD_URL is empty. Refusing to build a release with disabled cloud auth."
}

try {
  $uri = [System.Uri]::new($cloudUrl)
} catch {
  Fail "APPFLOWY_CLOUD_URL is not a valid URI."
}

if (-not $uri.IsAbsoluteUri -or ($uri.Scheme -ne 'https' -and $uri.Scheme -ne 'http')) {
  Fail "APPFLOWY_CLOUD_URL must be an absolute http(s) URI."
}

if ([string]::IsNullOrWhiteSpace($baseWebDomain)) {
  Fail "BASE_WEB_DOMAIN is empty. Share links would fall back to the default web domain."
}

try {
  $baseWebUri = [System.Uri]::new($baseWebDomain)
} catch {
  Fail "BASE_WEB_DOMAIN is not a valid URI."
}

if (-not $baseWebUri.IsAbsoluteUri -or ($baseWebUri.Scheme -ne 'https' -and $baseWebUri.Scheme -ne 'http')) {
  Fail "BASE_WEB_DOMAIN must be an absolute http(s) URI."
}

if ($authenticatorType -notmatch '^\d+$') {
  Fail "AUTHENTICATOR_TYPE must be numeric."
}

if (@('2', '3', '4') -notcontains $authenticatorType) {
  Fail "AUTHENTICATOR_TYPE must enable cloud auth for release builds. Expected 2, 3, or 4."
}

if (-not (Test-Path -LiteralPath $generatedPath)) {
  Fail "Missing generated env file: $generatedPath. Run build_runner before release build."
}

$generatedContent = Get-Content -LiteralPath $generatedPath -Raw
$generatedMatch = [regex]::Match(
  $generatedContent,
  "static const String afCloudUrl = '([^']*)';"
)

if (-not $generatedMatch.Success) {
  Fail "Unable to read afCloudUrl from generated env file."
}

$generatedCloudUrl = $generatedMatch.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($generatedCloudUrl)) {
  Fail "Generated afCloudUrl is empty. Regenerate env.g.dart after restoring .env."
}

if ($generatedCloudUrl -ne $cloudUrl) {
  Fail "Generated afCloudUrl does not match .env APPFLOWY_CLOUD_URL. Regenerate env.g.dart."
}

$generatedBaseWebDomainMatch = [regex]::Match(
  $generatedContent,
  "static const String baseWebDomain = '([^']*)';"
)

if (-not $generatedBaseWebDomainMatch.Success) {
  Fail "Unable to read baseWebDomain from generated env file."
}

$generatedBaseWebDomain = $generatedBaseWebDomainMatch.Groups[1].Value
if ($generatedBaseWebDomain -ne $baseWebDomain) {
  Fail "Generated baseWebDomain does not match .env BASE_WEB_DOMAIN. Regenerate env.g.dart."
}

Write-Host "Release env OK: APPFLOWY_CLOUD_URL length=$($cloudUrl.Length), BASE_WEB_DOMAIN=$baseWebDomain, AUTHENTICATOR_TYPE=$authenticatorType"
