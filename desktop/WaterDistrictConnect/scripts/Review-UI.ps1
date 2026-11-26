param([switch]$UseExistingLocalDemo)
$ErrorActionPreference = 'Stop'
$reviewRoot = Split-Path $PSScriptRoot -Parent
if ($UseExistingLocalDemo) {
    $reviewSettings = Get-Content -LiteralPath (Join-Path $reviewRoot '.local/demo-settings.json') -Raw | ConvertFrom-Json
    $env:MWD_TEST_ADMIN = "Host=127.0.0.1;Port=$($reviewSettings.Port);Database=postgres;Username=mwd_demo;Password=$($reviewSettings.Password);Timeout=5"
}
if ([string]::IsNullOrWhiteSpace($env:MWD_TEST_ADMIN)) { throw 'Configure MWD_TEST_ADMIN or use -UseExistingLocalDemo. UI review uses only generated disposable PostgreSQL data.' }
Push-Location $reviewRoot
try {
    dotnet run --project tools/UiReview -c Release
    if ($LASTEXITCODE -ne 0) { throw 'UI rendering verification failed.' }
} finally { Pop-Location }
