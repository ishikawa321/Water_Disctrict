param([switch]$UseExistingLocalDemo, [switch]$Migrate)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Start-Phase1.ps1') -UseExistingLocalDemo:$UseExistingLocalDemo -ConfigureOnly
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Migrate) {
        dotnet run --project WaterDistrictConnect -- --migrate
        if ($LASTEXITCODE -ne 0) { throw 'Migration failed. Check migration-error.txt and database configuration.' }
    }
    dotnet run --project WaterDistrictConnect --no-launch-profile
    if ($LASTEXITCODE -ne 0) { throw 'Application exited unsuccessfully.' }
} finally { Pop-Location }
