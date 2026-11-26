param(
    [string]$FlutterExecutable = 'flutter',
    [string]$SigningDirectory = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.waterdistrict/android-release')
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$privateDirectory = [IO.Path]::GetFullPath($SigningDirectory)
$propertiesPath = Join-Path $privateDirectory 'key.properties'
$keystorePath = Join-Path $privateDirectory 'waterdistrict-release.jks'

New-Item -ItemType Directory -Force -Path $privateDirectory | Out-Null
# New keys are private to this Windows user. Never replace an existing key:
# every subsequent APK update must be signed with this same certificate.
if (!(Test-Path -LiteralPath $propertiesPath)) {
    if (Test-Path -LiteralPath $keystorePath) { throw 'Keystore already exists but its credentials are missing. Restore the original key.properties; do not create a replacement key.' }
    $signingIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $privateDirectory /inheritance:r /grant:r "$($signingIdentity):(OI)(CI)F" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not protect the signing directory.' }
    $randomBytes = New-Object byte[] 32
    $randomSource = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $randomSource.GetBytes($randomBytes) } finally { $randomSource.Dispose() }
    $signingPassword = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    $env:WATERDISTRICT_KEYTOOL_PASSWORD = $signingPassword
    try {
        & keytool.exe -genkeypair -v -keystore $keystorePath -storetype PKCS12 -alias waterdistrict-release -keyalg RSA -keysize 3072 -validity 10000 -storepass:env WATERDISTRICT_KEYTOOL_PASSWORD -keypass:env WATERDISTRICT_KEYTOOL_PASSWORD -dname 'CN=Water District Connect, OU=Student Project, O=Water District Connect, L=Maramag, ST=Bukidnon, C=PH'
        if ($LASTEXITCODE -ne 0) { throw 'Android release keystore generation failed.' }
        $propertyText = "storeFile=$($keystorePath.Replace('\','/'))`nstorePassword=$signingPassword`nkeyAlias=waterdistrict-release`nkeyPassword=$signingPassword`n"
        [IO.File]::WriteAllText($propertiesPath, $propertyText, [Text.UTF8Encoding]::new($false))
    } finally {
        Remove-Item Env:WATERDISTRICT_KEYTOOL_PASSWORD -ErrorAction SilentlyContinue
        $signingPassword = $null
        $propertyText = $null
    }
}
if (!(Test-Path -LiteralPath $keystorePath)) { throw 'The signing keystore is missing. Restore the original signing backup.' }
$previousSigningPath = $env:WATERDISTRICT_ANDROID_SIGNING_PROPERTIES
$env:WATERDISTRICT_ANDROID_SIGNING_PROPERTIES = $propertiesPath
Push-Location $repoRoot
try {
    $versionLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^version:' } | Select-Object -First 1
    $releaseVersion = (($versionLine -split ':',2)[1].Trim() -split '\+')[0]
    $symbolDirectory = Join-Path $repoRoot "artifacts/android/symbols/$releaseVersion"
    & $FlutterExecutable build apk --release --obfuscate "--split-debug-info=$symbolDirectory"
    if ($LASTEXITCODE -ne 0) { throw 'Android release build failed.' }
    $releaseDirectory = Join-Path $repoRoot 'artifacts/android'
    New-Item -ItemType Directory -Force -Path $releaseDirectory | Out-Null
    $destination = Join-Path $releaseDirectory "WaterDistrictConnect-$releaseVersion.apk"
    Copy-Item -LiteralPath (Join-Path $repoRoot 'build/app/outputs/flutter-apk/app-release.apk') -Destination $destination
    $digest = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$destination.sha256", "$digest  $([IO.Path]::GetFileName($destination))`n", [Text.UTF8Encoding]::new($false))
    Write-Output "Signed APK: $destination"
    Write-Output "SHA-256: $digest"
    Write-Output "Keep a private backup of $privateDirectory. Do not upload its keystore or credentials."
} finally {
    $env:WATERDISTRICT_ANDROID_SIGNING_PROPERTIES = $previousSigningPath
    Pop-Location
}
