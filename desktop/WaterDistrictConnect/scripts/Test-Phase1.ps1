param([switch]$UseExistingLocalDemo, [string]$PostgresBin = 'C:\Program Files\PostgreSQL\18\bin')
$ErrorActionPreference = 'Stop'
$phaseRoot = Split-Path $PSScriptRoot -Parent
if ($UseExistingLocalDemo) {
    . (Join-Path $PSScriptRoot 'Start-Phase1.ps1') -UseExistingLocalDemo -ConfigureOnly
    $phaseSettings = Get-Content -LiteralPath (Join-Path $phaseRoot '.local/demo-settings.json') -Raw | ConvertFrom-Json
    # Only use the already configured server. Create the dedicated test database if missing; never drop it.
    $env:PGPASSWORD = $phaseSettings.Password
    try {
        $phaseExists = & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p $phaseSettings.Port -U mwd_demo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='mwd_phase1_test'"
        if ($LASTEXITCODE -ne 0) { throw 'Existing local PostgreSQL server unavailable. No service or credentials were changed.' }
        if ($phaseExists -ne '1') {
            & (Join-Path $PostgresBin 'createdb.exe') -h 127.0.0.1 -p $phaseSettings.Port -U mwd_demo mwd_phase1_test
            if ($LASTEXITCODE -ne 0) { throw 'Cannot create dedicated Phase 1 test database.' }
        }
    } finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
    $env:MWD_PHASE1_TEST_CONNECTION = "Host=127.0.0.1;Port=$($phaseSettings.Port);Database=mwd_phase1_test;Username=mwd_demo;Password=$($phaseSettings.Password);Timeout=5"
}
Push-Location $phaseRoot
try {
    dotnet test WaterDistrictConnect.UnitTests --filter 'Phase=1' --logger 'trx;LogFileName=phase1-unit.trx' --results-directory TestResults
    if ($LASTEXITCODE -ne 0) { throw 'Phase 1 unit tests failed.' }
    dotnet test WaterDistrictConnect.IntegrationTests --filter 'Phase=1' --logger 'trx;LogFileName=phase1-postgresql.trx' --results-directory TestResults
    if ($LASTEXITCODE -ne 0) { throw 'Phase 1 PostgreSQL tests failed.' }
} finally { Pop-Location }
