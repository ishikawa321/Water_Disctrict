param([switch]$UseExistingLocalDemo)
$ErrorActionPreference = 'Stop'
$phaseRoot = Split-Path $PSScriptRoot -Parent
if ($UseExistingLocalDemo) {
    $phaseSettings = Get-Content -LiteralPath (Join-Path $phaseRoot '.local/demo-settings.json') -Raw | ConvertFrom-Json
    $env:MWD_TEST_ADMIN = "Host=127.0.0.1;Port=$($phaseSettings.Port);Database=postgres;Username=mwd_demo;Password=$($phaseSettings.Password);Timeout=5"
}
if ([string]::IsNullOrWhiteSpace($env:MWD_TEST_ADMIN)) { throw 'Set MWD_TEST_ADMIN to a server permitting disposable database creation, or use -UseExistingLocalDemo. No application database will be reset.' }
Push-Location $phaseRoot
try {
    dotnet test WaterDistrictConnect.UnitTests -c Release --logger 'trx;LogFileName=phase2-unit.trx' --results-directory TestResults
    if ($LASTEXITCODE -ne 0) { throw 'Unit tests failed.' }
    dotnet test WaterDistrictConnect.IntegrationTests -c Release --filter 'Phase=2' --logger 'trx;LogFileName=phase2-postgresql.trx' --results-directory TestResults
    if ($LASTEXITCODE -ne 0) { throw 'Phase 2 PostgreSQL tests failed.' }
} finally { Pop-Location }
