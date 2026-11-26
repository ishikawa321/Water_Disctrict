param([switch]$UseExistingLocalDemo, [switch]$Migrate, [switch]$ConfigureOnly)
$ErrorActionPreference = 'Stop'
$phaseRoot = Split-Path $PSScriptRoot -Parent
if ($UseExistingLocalDemo) {
    $settingsPath = Join-Path $phaseRoot '.local/demo-settings.json'
    if (!(Test-Path -LiteralPath $settingsPath)) { throw 'No existing local demo configuration. Configure MWD_CONNECTION or appsettings.local.json. No server will be installed or reconfigured.' }
    $phaseSettings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $env:MWD_CONNECTION = "Host=127.0.0.1;Port=$($phaseSettings.Port);Database=mwd_demo;Username=mwd_demo;Password=$($phaseSettings.Password);Timeout=5"
    $env:MWD_DEMO = 'true'
}
# Phase 1 seeds identity/reference records only. Existing operational records are retained.
$env:MWD_SAMPLE = 'false'
if (!$ConfigureOnly) {
    Push-Location $phaseRoot
    try {
        if ($Migrate) {
            dotnet run --project WaterDistrictConnect -- --migrate
            if ($LASTEXITCODE -ne 0) { throw 'Migration failed. Check connection configuration and migration-error.txt.' }
        }
        dotnet run --project WaterDistrictConnect --no-launch-profile
        if ($LASTEXITCODE -ne 0) { throw 'Application exited unsuccessfully.' }
    } finally { Pop-Location }
}
