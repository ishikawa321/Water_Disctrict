param([string]$PostgresBin = 'C:\Program Files\PostgreSQL\18\bin')
$ErrorActionPreference = 'Stop'
# Uses only the isolated server. Tests create/drop their own generated mwd_test_<GUID> databases.
. (Join-Path $PSScriptRoot 'Start-LocalDemo.ps1') -PostgresBin $PostgresBin -SetupOnly
Push-Location (Split-Path $PSScriptRoot -Parent)
try { dotnet test WaterDistrictConnect.IntegrationTests --logger 'trx;LogFileName=postgresql.trx' --results-directory TestResults; if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL integration tests failed.' } } finally { Pop-Location }
