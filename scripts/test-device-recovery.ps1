param([Parameter(Mandatory=$true)][string]$Serial,[int]$SeedVersion=11000)
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskRoot
$taskSdk=Join-Path $env:LOCALAPPDATA 'Android/Sdk'
$taskAdb=Join-Path $taskSdk 'platform-tools/adb.exe'
$taskAapt=Join-Path $taskSdk 'build-tools/36.0.0/aapt.exe'
$taskPackage='com.example.gestionale_radio.qa'
function Read-QAResult([string]$phase) {
  for($attempt=0;$attempt -lt 30;$attempt++) {
    $result=& $taskAdb -s $Serial shell run-as $taskPackage cat files/qa-upgrade-result.json 2>$null
    if($LASTEXITCODE -eq 0) {try {$proof=$result|ConvertFrom-Json;if($proof.phase -eq $phase){if(!$proof.success){throw "QA $phase failed: $($proof.error)"};return $proof}}catch [System.ArgumentException] {}}
    Start-Sleep -Seconds 1
  }
  throw "No completed QA result for $phase."
}
function Start-QAPhase([string]$phase) {
  & $taskAdb -s $Serial shell am force-stop $taskPackage | Out-Null
  & $taskAdb -s $Serial shell am start -n "$taskPackage/com.example.gestionale_radio.MainActivity" --es radiotechQaPhase $phase | Out-Null
  if($LASTEXITCODE -ne 0){throw 'QA launch failed.'}
  Read-QAResult $phase
}
function Build-QA([int]$version) {
  flutter build apk --debug --target integration_test/upgrade_recovery_app.dart "--build-number=$version" *> qa-upgrade-build.log
  if($LASTEXITCODE -ne 0){throw 'QA build failed; inspect qa-upgrade-build.log.'}
  $taskApk=Join-Path $taskRoot 'build/app/outputs/flutter-apk/app-debug.apk'
  $identity=& $taskAapt dump badging $taskApk | Select-Object -First 1
  if($identity -notmatch "name='com.example.gestionale_radio.qa'" -or $identity -notmatch "versionCode='$version'"){throw 'Refusing to install a non-QA APK.'}
  & $taskAdb -s $Serial install -r $taskApk | Out-Null
  if($LASTEXITCODE -ne 0){throw 'QA install failed.'}
}
$taskPrevious=$env:RADIOTECH_QA_BUILD
$taskPreviousApp=$env:ANDROID_APPLICATION_ID
$taskPreviousLabel=$env:ANDROID_APP_LABEL
try {
  $env:RADIOTECH_QA_BUILD='true'
  $env:ANDROID_APPLICATION_ID=$taskPackage
  $env:ANDROID_APP_LABEL='RadioTech QA'
  Build-QA $SeedVersion
  $seed=Start-QAPhase 'seed'
  $restart=Start-QAPhase 'restart'
  Build-QA ($SeedVersion+1)
  $upgrade=Start-QAPhase 'upgrade'
  @{device=$Serial;seed=$seed;restart=$restart;upgrade=$upgrade}|ConvertTo-Json -Depth 4
} finally {$env:RADIOTECH_QA_BUILD=$taskPrevious;$env:ANDROID_APPLICATION_ID=$taskPreviousApp;$env:ANDROID_APP_LABEL=$taskPreviousLabel}
