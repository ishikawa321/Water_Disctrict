# Flutter copies every file under web/. Stage only its public resources because
# this repository also keeps the separate Next.js application in that directory.
param([string]$Mode = 'release')
$ErrorActionPreference = 'Stop'
if ($Mode -notin @('release', 'profile', 'debug')) { throw 'Unsupported build mode.' }
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stagingRoot = Join-Path $projectRoot 'build/flutter-web-source'
$outputRoot = Join-Path $projectRoot 'build/web'
New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
foreach ($name in @('lib', 'assets', 'pubspec.yaml', 'pubspec.lock', '.metadata', 'analysis_options.yaml')) {
    $source = Join-Path $projectRoot $name
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $stagingRoot -Recurse -Force
    }
}
$stagingWeb = Join-Path $stagingRoot 'web'
New-Item -ItemType Directory -Path $stagingWeb -Force | Out-Null
foreach ($name in @('index.html', 'manifest.json', 'favicon.png', 'district-logo.png', 'icons', 'flutter_bootstrap.js')) {
    $source = Join-Path (Join-Path $projectRoot 'web') $name
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $stagingWeb -Recurse -Force
    }
}
Push-Location $stagingRoot
try {
    & flutter pub get --offline
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed.' }
    & flutter build web "--$Mode" --output $outputRoot
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
} finally {
    Pop-Location
}
foreach ($name in @('.env.local', '.env', '.next', 'node_modules', 'src', 'tests')) {
    if (Test-Path -LiteralPath (Join-Path $outputRoot $name)) {
        throw "Unexpected Next.js input in Flutter output: $name"
    }
}
Write-Output "Flutter-only web release: $outputRoot"
