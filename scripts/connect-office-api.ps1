param(
    [Parameter(Mandatory = $true)][string]$ApiUrl,
    [string]$VercelExecutable = ''
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
Push-Location $repoRoot
try {
    # No configuration change until the original API and shared DB are healthy.
    & node (Join-Path $PSScriptRoot 'check-office-api.mjs') $ApiUrl
    if ($LASTEXITCODE -ne 0) { throw 'The office API failed validation. Vercel configuration was not changed.' }
    function Invoke-Vercel {
        param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArguments)
        if ($VercelExecutable) { & $VercelExecutable @CliArguments }
        else { & npx.cmd --yes vercel@66.6.0 @CliArguments }
        if ($LASTEXITCODE -ne 0) { throw 'Vercel could not complete this operation.' }
    }
    Invoke-Vercel env add WATERDISTRICT_API_URL --environment production --value $ApiUrl.TrimEnd('/') --force --yes --no-sensitive
    Invoke-Vercel deploy --prod --yes --local-config web/vercel.json
} finally { Pop-Location }
