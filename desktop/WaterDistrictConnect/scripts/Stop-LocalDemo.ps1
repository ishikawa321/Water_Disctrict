param([string]$PostgresBin = 'C:\Program Files\PostgreSQL\18\bin')
$cluster = Join-Path (Split-Path $PSScriptRoot -Parent) '.local/postgres'
if (Test-Path -LiteralPath $cluster) { & (Join-Path $PostgresBin 'pg_ctl.exe') stop -D $cluster -m fast -w }
