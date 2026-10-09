param(
    [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
    [string]$BuildNumber = '1',
    [string]$AppName = 'RadioTech',
    [string]$AppSubtitle = 'Gestione operativa',
    [string]$CompanyName = 'RadioTech',
    [string]$SupportEmail = '',
    [string]$AndroidApplicationId = '',
    [string]$AndroidAppName = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root

$target = [Uri]$ApiBaseUrl
if (!$target.IsAbsoluteUri -or $target.Scheme -ne 'https' -or $target.UserInfo -or $target.Query -or $target.Fragment -or $target.AbsolutePath -ne '/') {
    throw 'API_BASE_URL must be the canonical HTTPS origin.'
}
if ($BuildNumber -notmatch '^\d+$' -or [int]$BuildNumber -lt 1) {
    throw 'Use a positive build number greater than the last published version.'
}
if (!(Test-Path -LiteralPath 'android/key.properties') -and !$env:ANDROID_KEYSTORE_PATH) {
    throw 'Configure the existing Android upload key before building a release.'
}

if ($AndroidApplicationId) {
    if ($AndroidApplicationId -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$') {
        throw 'ANDROID_APPLICATION_ID is not a valid Android application ID.'
    }
    $env:ANDROID_APPLICATION_ID = $AndroidApplicationId
}
$env:ANDROID_APP_NAME = $(if ($AndroidAppName) { $AndroidAppName } else { $AppName })

$health = Invoke-RestMethod -Uri ($ApiBaseUrl.TrimEnd('/') + '/api/v1/health') -TimeoutSec 15
if ($health.service -ne 'radiotech-backend' -or $health.status -ne 'UP') {
    throw 'The URL does not serve a healthy RadioTech backend.'
}
$ready = Invoke-RestMethod -Uri ($ApiBaseUrl.TrimEnd('/') + '/actuator/health/readiness') -TimeoutSec 15
if ($ready.status -ne 'UP') {
    throw 'The backend is not production ready.'
}

flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution or lockfile verification failed.' }

dart format --output=none --set-exit-if-changed lib test
if ($LASTEXITCODE -ne 0) { throw 'Dart formatting check failed.' }

flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }

flutter test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }

$defines = @(
    "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))",
    "--dart-define=APP_CHECK_DEBUG=false",
    "--dart-define=APP_NAME=$AppName",
    "--dart-define=APP_DISPLAY_NAME=$AppName",
    "--dart-define=APP_SUBTITLE=$AppSubtitle",
    "--dart-define=APP_COMPANY=$CompanyName",
    "--dart-define=APP_SUPPORT_EMAIL=$SupportEmail",
    "--dart-define=APP_PDF_BRAND=$AppName Operations Suite",
    "--dart-define=APP_ASSET_PREFIX=$AppName"
)

flutter build appbundle --release "--build-number=$BuildNumber" @defines --obfuscate --split-debug-info=release-symbols
if ($LASTEXITCODE -ne 0) { throw 'Signed release build failed.' }

Write-Output 'Signed AAB: build/app/outputs/bundle/release/app-release.aab'
Write-Output "Product: $AppName"
$effectiveApplicationId = if ($env:ANDROID_APPLICATION_ID) { $env:ANDROID_APPLICATION_ID } else { 'com.example.gestionale_radio' }
Write-Output "Android application ID: $effectiveApplicationId"
Write-Output 'Store release-symbols privately alongside the exact build number.'
