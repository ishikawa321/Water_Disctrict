[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$desktopRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $desktopRoot ('artifacts/release/' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$releaseRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $releaseRoot) { throw 'Choose a new output directory. Existing artifacts are never overwritten.' }
New-Item -ItemType Directory -Path $releaseRoot | Out-Null
foreach ($project in @('WaterDistrict.Desktop', 'WaterDistrict.Api')) {
    $target = if ($project -eq 'WaterDistrict.Desktop') { 'Desktop' } else { 'Api' }
    dotnet publish (Join-Path $desktopRoot "src/$project/$project.csproj") -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false -o (Join-Path $releaseRoot $target) --nologo
    if ($LASTEXITCODE -ne 0) { throw "Publish failed: $project" }
}
dotnet publish (Join-Path $desktopRoot 'tools/WaterDistrict.Database/WaterDistrict.Database.csproj') -c Release -r win-x64 --self-contained true -p:PublishTrimmed=false -o (Join-Path $releaseRoot 'Database') --nologo
if ($LASTEXITCODE -ne 0) { throw 'Publish failed: database tool' }
if (Get-ChildItem -LiteralPath $releaseRoot -Recurse -Filter appsettings.Local.json) { throw 'Local configuration unexpectedly included. Do not distribute this output.' }
Copy-Item -LiteralPath (Join-Path $desktopRoot 'scripts/launch.ps1') -Destination (Join-Path $releaseRoot 'launch.ps1')
Copy-Item -LiteralPath (Join-Path $desktopRoot 'README.md') -Destination (Join-Path $releaseRoot 'SETUP.md')
Copy-Item -LiteralPath (Join-Path $desktopRoot '../docs/release-and-demonstration.md') -Destination (Join-Path $releaseRoot 'RELEASE.md')
New-Item -ItemType Directory -Path (Join-Path $releaseRoot 'Docs') | Out-Null
foreach ($document in @('admin-staff-mobile-comparison.md','acceptance-verification.md','database-contract.md','office-account-setup.md','release-and-demonstration.md')) {
    Copy-Item -LiteralPath (Join-Path $desktopRoot "../docs/$document") -Destination (Join-Path $releaseRoot "Docs/$document")
}
$manifest = Get-ChildItem -LiteralPath $releaseRoot -Recurse -File | ForEach-Object {
    [PSCustomObject]@{ Path = $_.FullName.Substring($releaseRoot.Length + 1); SHA256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
}
$manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $releaseRoot 'checksums.json') -Encoding UTF8
Write-Output "Published Windows x64 release: $releaseRoot"
