param([string]$ApiBaseUrl = 'https://radiotechwebapp.onrender.com', [string]$BuildNumber, [string]$UpdateManifestUrl)
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
$expectedSigningSha256 = $env:ANDROID_EXPECTED_SIGNING_SHA256
if ($expectedSigningSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'Set ANDROID_EXPECTED_SIGNING_SHA256 to the production certificate fingerprint.' }
$updateDefines = @()
if ($UpdateManifestUrl) {
    $manifestTarget = [Uri]$UpdateManifestUrl
    if (!$manifestTarget.IsAbsoluteUri -or $manifestTarget.Scheme -ne 'https' -or $manifestTarget.Port -ne 443 -or $manifestTarget.UserInfo -or $manifestTarget.Query -or $manifestTarget.Fragment -or !$manifestTarget.AbsolutePath.EndsWith('.json')) { throw 'Use an HTTPS manifest URL without credentials, query or fragment.' }
    $env:APK_UPDATE_ORIGIN = $manifestTarget.GetLeftPart([UriPartial]::Authority)
    $updateDefines = @("--dart-define=UPDATE_MANIFEST_URL=$UpdateManifestUrl", "--dart-define=APK_UPDATE_ORIGIN=$env:APK_UPDATE_ORIGIN")
} else { $env:APK_UPDATE_ORIGIN = '' }
$health = Invoke-RestMethod -Uri ($ApiBaseUrl.TrimEnd('/') + '/api/v1/health') -TimeoutSec 65
if ($health.service -ne 'radiotech-backend' -or $health.status -ne 'UP') { throw 'The URL does not serve a healthy RadioTech backend.' }
$ready = Invoke-RestMethod -Uri ($ApiBaseUrl.TrimEnd('/') + '/actuator/health/readiness') -TimeoutSec 65
if ($ready.status -ne 'UP') { throw 'The backend is not production ready.' }
flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution or lockfile verification failed.' }
dart format --output=none --set-exit-if-changed lib test
if ($LASTEXITCODE -ne 0) { throw 'Dart formatting check failed.' }
flutter analyze
if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
flutter build appbundle --release "--build-number=$BuildNumber" "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))" --dart-define=APP_CHECK_DEBUG=false @updateDefines --obfuscate --split-debug-info=release-symbols
if ($LASTEXITCODE -ne 0) { throw 'Signed release build failed.' }
flutter build apk --release "--build-number=$BuildNumber" "--dart-define=API_BASE_URL=$($ApiBaseUrl.TrimEnd('/'))" --dart-define=APP_CHECK_DEBUG=false @updateDefines --obfuscate --split-debug-info=release-symbols
if ($LASTEXITCODE -ne 0) { throw 'Signed APK build failed.' }
$sdkDirectory = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$signer = Get-ChildItem -LiteralPath (Join-Path $sdkDirectory 'build-tools') -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (!$signer) { throw 'Android apksigner is required to verify the production artifact.' }
$certificateReport = (& $signer verify --verbose --print-certs build/app/outputs/flutter-apk/app-release.apk 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $certificateReport -notmatch '(?:Signer #1|V[234](?:\.\d+)? Signer):? certificate SHA-256 digest: ([a-f0-9]+)' -or $Matches[1].ToLowerInvariant() -ne $expectedSigningSha256.ToLowerInvariant() -or $certificateReport -match 'Android Debug') { throw 'The APK does not have the verified RadioTech production certificate.' }
New-Item -ItemType Directory -Force -Path artifacts | Out-Null
$productName = if ($env:ANDROID_APP_LABEL) { $env:ANDROID_APP_LABEL -replace '[^A-Za-z0-9._-]+','-' } else { 'RadioTech' }
$releaseName = "$productName-$($releaseVersion.Groups[1].Value)-$BuildNumber"
Copy-Item -LiteralPath build/app/outputs/flutter-apk/app-release.apk -Destination "artifacts/$releaseName.apk"
Copy-Item -LiteralPath build/app/outputs/bundle/release/app-release.aab -Destination "artifacts/$releaseName.aab"
Write-Output 'Signed AAB: build/app/outputs/bundle/release/app-release.aab'
Write-Output "Signed APK with verified production certificate: artifacts/$releaseName.apk"
Write-Output 'Store release-symbols privately alongside the exact build number.'

if ($UpdateManifestUrl) {
    $applicationId = if ($env:ANDROID_APPLICATION_ID) { $env:ANDROID_APPLICATION_ID } else { 'com.example.gestionale_radio' }
    $download = [Uri]::new($manifestTarget, "$releaseName.apk").AbsoluteUri
    $manifest = [ordered]@{ available=$true; applicationId=$applicationId; versionName=$releaseVersion.Groups[1].Value; versionCode=[int]$BuildNumber; signingSha256=$expectedSigningSha256.ToLowerInvariant(); filename="$releaseName.apk"; channel='PRIVATE_SITE'; sha256=(Get-FileHash -LiteralPath "artifacts/$releaseName.apk" -Algorithm SHA256).Hash.ToLowerInvariant(); downloadUrl=$download }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath artifacts/latest.json -Encoding utf8NoBOM
    "È disponibile RadioTech $($releaseVersion.Groups[1].Value). Apri l'app e seleziona Controlla aggiornamenti. L'app verificherà il pacchetto prima dell'installazione." | Set-Content -LiteralPath artifacts/avviso-aggiornamento.txt -Encoding utf8NoBOM
}
