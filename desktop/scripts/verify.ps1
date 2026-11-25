[CmdletBinding()]
param([switch]$RequirePostgres)
$ErrorActionPreference = 'Stop'
$desktopRoot = Split-Path $PSScriptRoot -Parent
if ($RequirePostgres -and -not $env:WATERDISTRICT_TEST_POSTGRES) {
    throw 'Set WATERDISTRICT_TEST_POSTGRES to a local PostgreSQL administration connection. Tests create and drop uniquely named test databases.'
}
dotnet build (Join-Path $desktopRoot 'WaterDistrict.sln') --nologo
if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
dotnet test (Join-Path $desktopRoot 'WaterDistrict.sln') --no-build --nologo --logger 'trx;LogFileName=verification.trx' --results-directory (Join-Path $desktopRoot 'artifacts/test-results')
if ($LASTEXITCODE -ne 0) { throw 'Verification failed.' }
if (-not $env:WATERDISTRICT_TEST_POSTGRES) { Write-Warning 'PostgreSQL tests were skipped; this run cannot establish relational integrity or transaction correctness.' }
