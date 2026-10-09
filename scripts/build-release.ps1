param([string]$ApiBaseUrl = 'https://radiotechwebapp.onrender.com', [string]$BuildNumber)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root
$releaseVersion = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*([^+\s]+)\+(\d+)')
if (!$releaseVersion.Success) { throw 'The application version is missing.' }
if (!$BuildNumber) { $BuildNumber = $releaseVersion.Groups[2].Value }
$target = [Uri]$ApiBaseUrl
if (!$target.IsAbsoluteUri -or $target.Scheme -ne 'https' -or $target.UserInfo -or $target.Query -or $target.Fragment -or $target.AbsolutePath -ne '/') {
    throw 'API_BASE_URL must be the canonical HTTPS origin.'
}
if ($BuildNumber -notmatch '^\d+$' -or [int]$BuildNumber -lt [int]$releaseVersion.Groups[2].Value) { throw 'The build number must not be lower than the repository version.' }
if (!(Test-Path -LiteralPath 'android/key.properties') -and !(Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.radiotech/signing/key.properties')) -and !$env:ANDROID_KEYSTORE_PATH -and !$env:ANDROID_KEY_PROPERTIES_PATH) { throw 'Configure the existing Android upload key before building a release.' }
$health = Invoke-RestMethod -Uri ($ApiBaseUrl.TrimEnd('/') + '/api/v1/health') -TimeoutSec 65
if ($health.service -ne 'radiotech-backend' -or $health.status -ne 'UP') { throw 'The URL does not serve a healthy RadioTech backend.' }
$ready = Invoke-RestMethod -Uri ($ApiBaseUrl.TrimEnd('/') + '/actuator/health/readiness') -TimeoutSec 65
if ($ready.status -ne 'UP') { throw 'The backend is not production ready.' }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
flutter build appbundle --release "--build-number=$BuildNumber" "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))" --dart-define=APP_CHECK_DEBUG=false --obfuscate --split-debug-info=release-symbols
if ($LASTEXITCODE -ne 0) { throw 'Signed release build failed.' }
flutter build apk --release "--build-number=$BuildNumber" "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))" --dart-define=APP_CHECK_DEBUG=false --obfuscate --split-debug-info=release-symbols
if ($LASTEXITCODE -ne 0) { throw 'Signed APK build failed.' }
$sdkDirectory = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$signer = Get-ChildItem -LiteralPath (Join-Path $sdkDirectory 'build-tools') -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$signer) { throw 'Android apksigner is required to verify the production artifact.' }
$certificateReport = (& $signer verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $certificateReport -notmatch '(?:Signer #1|V[234](?:\.\d+)? Signer):? certificate SHA-256 digest: ([a-f0-9]+)' -or $Matches[1] -ne '73005990b6bad93b1bb3383121f6dcc2293b3e5e3a60e1ae7eaf09a7d97c4fa4' -or $certificateReport -match 'Android Debug') { throw 'The APK does not have the verified RadioTech production certificate.' }
New-Item -ItemType Directory -Force -Path artifacts | Out-Null
$releaseName = "RadioTech-$($releaseVersion.Groups[1].Value)-$BuildNumber"
Copy-Item -LiteralPath build/app/outputs/flutter-apk/app-release.apk -Destination "artifacts/$releaseName.apk"
Copy-Item -LiteralPath build/app/outputs/bundle/release/app-release.aab -Destination "artifacts/$releaseName.aab"
Write-Output 'Signed AAB: build/app/outputs/bundle/release/app-release.aab'
Write-Output "Signed APK with verified production certificate: artifacts/$releaseName.apk"
Write-Output 'Store release-symbols privately alongside the exact build number.'
