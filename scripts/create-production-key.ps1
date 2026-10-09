param([string]$SigningDirectory = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.radiotech/signing'))
$ErrorActionPreference = 'Stop'
$mobileRoot = Split-Path -Parent $PSScriptRoot
$signingStore = Join-Path $SigningDirectory 'radiotech-production.p12'
$propertiesPath = Join-Path $mobileRoot 'android/key.properties'
if (Test-Path -LiteralPath $propertiesPath) { throw 'A signing configuration already exists; it must be preserved and reviewed.' }
if (Test-Path -LiteralPath $signingStore) { throw 'The production keystore already exists; never replace it.' }
New-Item -ItemType Directory -Force -Path $SigningDirectory | Out-Null
if ($env:OS -eq 'Windows_NT') {
    $signingAcl = Get-Acl -LiteralPath $SigningDirectory
    $signingAcl.SetAccessRuleProtection($true, $false)
    $signingAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    Set-Acl -LiteralPath $SigningDirectory -AclObject $signingAcl
}
$signingBytes = [byte[]]::new(32)
[Security.Cryptography.RandomNumberGenerator]::Fill($signingBytes)
$signingPassword = [Convert]::ToBase64String($signingBytes)
$env:RADIOTECH_NEW_KEY_PASSWORD = $signingPassword
try {
    & keytool -genkeypair -keystore $signingStore -storetype PKCS12 -alias radiotech-production -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10000 -dname 'CN=RadioTech, O=RadioTech, C=IT' -storepass:env RADIOTECH_NEW_KEY_PASSWORD -keypass:env RADIOTECH_NEW_KEY_PASSWORD
    if ($LASTEXITCODE -ne 0) { throw 'Production keystore generation failed.' }
    $privateProperties = "storeFile=$($signingStore.Replace('\','/'))`nstorePassword=$signingPassword`nkeyAlias=radiotech-production`nkeyPassword=$signingPassword`n"
    $protectedProperties = Join-Path $SigningDirectory 'key.properties'
    [IO.File]::WriteAllText($protectedProperties, $privateProperties)
    & keytool -exportcert -keystore $signingStore -alias radiotech-production -storepass:env RADIOTECH_NEW_KEY_PASSWORD -file (Join-Path $SigningDirectory 'radiotech-production.cer')
    if ($LASTEXITCODE -ne 0) { throw 'Certificate export failed.' }
    $certificateBytes = [IO.File]::ReadAllBytes((Join-Path $SigningDirectory 'radiotech-production.cer'))
    $fingerprints = @{alias='radiotech-production';sha1=[Convert]::ToHexString([Security.Cryptography.SHA1]::HashData($certificateBytes));sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($certificateBytes))}
    $fingerprints | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $SigningDirectory 'certificate.json')
    Write-Output "Production signing identity prepared in $SigningDirectory. Preserve the keystore and password in a separate encrypted backup."
} finally { Remove-Item Env:RADIOTECH_NEW_KEY_PASSWORD -ErrorAction SilentlyContinue }
