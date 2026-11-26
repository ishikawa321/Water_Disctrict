param([string]$PostgresBin = 'C:\Program Files\PostgreSQL\18\bin', [switch]$SetupOnly)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$localRoot = Join-Path $taskRoot '.local'
$cluster = Join-Path $localRoot 'postgres'
$settingsPath = Join-Path $localRoot 'demo-settings.json'
New-Item -ItemType Directory -Force -Path $localRoot | Out-Null
if (!(Test-Path -LiteralPath (Join-Path $PostgresBin 'initdb.exe'))) { throw 'Supply -PostgresBin pointing to existing PostgreSQL binaries. This script does not install PostgreSQL.' }
if (!(Test-Path -LiteralPath $settingsPath)) {
    if (Test-Path -LiteralPath $cluster) { throw 'A cluster already exists without demo settings. Refusing to replace it.' }
    $randomBytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($randomBytes)
    $rng.Dispose()
    $demoPassword = [Convert]::ToBase64String($randomBytes)
    $pwPath = Join-Path $localRoot 'init-password.tmp'
    [IO.File]::WriteAllText($pwPath, $demoPassword)
    try {
        & (Join-Path $PostgresBin 'initdb.exe') -D $cluster -U mwd_demo -A scram-sha-256 --pwfile=$pwPath --encoding=UTF8 --locale=C
        if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the isolated cluster.' }
    } finally { Remove-Item -LiteralPath $pwPath -ErrorAction SilentlyContinue }
    @{ Password = $demoPassword; Port = 55481 } | ConvertTo-Json | Set-Content -LiteralPath $settingsPath
}
$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
& (Join-Path $PostgresBin 'pg_ctl.exe') status -D $cluster | Out-Null
if ($LASTEXITCODE -ne 0) {
    & (Join-Path $PostgresBin 'pg_ctl.exe') start -D $cluster -l (Join-Path $localRoot 'postgres.log') -o '-h 127.0.0.1 -p 55481' -w
    if ($LASTEXITCODE -ne 0) { throw 'Could not start the isolated server. Check .local/postgres.log and port 55481.' }
}
$env:MWD_CONNECTION = "Host=127.0.0.1;Port=55481;Database=mwd_demo;Username=mwd_demo;Password=$($settings.Password);Timeout=5"
$env:MWD_TEST_ADMIN = "Host=127.0.0.1;Port=55481;Database=postgres;Username=mwd_demo;Password=$($settings.Password);Timeout=5"
$env:MWD_DEMO = 'true'
$env:MWD_SAMPLE = 'false'
$env:PGPASSWORD = $settings.Password
try {
    $exists = & (Join-Path $PostgresBin 'psql.exe') -h 127.0.0.1 -p 55481 -U mwd_demo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='mwd_demo'"
    if ($LASTEXITCODE -ne 0) { throw 'Could not connect to the isolated server.' }
    if ($exists -ne '1') { & (Join-Path $PostgresBin 'createdb.exe') -h 127.0.0.1 -p 55481 -U mwd_demo mwd_demo; if ($LASTEXITCODE -ne 0) { throw 'Could not create demo database.' } }
} finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
if (!$SetupOnly) {
    Push-Location $taskRoot
    try {
        # Historical published artifacts may expose later-phase workflows. Always use current source.
        dotnet run --project WaterDistrictConnect -- --migrate
        if ($LASTEXITCODE -ne 0) { throw 'Migration failed. See migration-error.txt.' }
        dotnet run --project WaterDistrictConnect --no-launch-profile
    } finally { Pop-Location }
}

