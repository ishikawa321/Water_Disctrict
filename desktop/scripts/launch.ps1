# Run in a published release folder. The API exits when this desktop session closes.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$apiDirectory = Join-Path $PSScriptRoot 'Api'
$desktopDirectory = Join-Path $PSScriptRoot 'Desktop'
$apiExecutable = Join-Path $apiDirectory 'WaterDistrict.Api.exe'
$desktopExecutable = Join-Path $desktopDirectory 'WaterDistrict.Desktop.exe'
if (-not (Test-Path -LiteralPath $apiExecutable) -or -not (Test-Path -LiteralPath $desktopExecutable)) {
    throw 'Run this launcher from the published release directory.'
}
$officeApiProcess = Start-Process -FilePath $apiExecutable -ArgumentList @('--urls', 'http://127.0.0.1:5181') -WorkingDirectory $apiDirectory -WindowStyle Hidden -PassThru
try {
    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if ($officeApiProcess.HasExited) { throw 'The API could not start. Check configuration and whether port 5181 is already in use.' }
        try { $response = Invoke-WebRequest -Uri 'http://127.0.0.1:5181/health' -UseBasicParsing -TimeoutSec 1; $ready = $response.StatusCode -eq 200 } catch { }
        if ($ready) { break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw 'The local API did not become available.' }
    # Interactive application explicitly opened by the launcher user.
    $officeDesktopProcess = Start-Process -FilePath $desktopExecutable -WorkingDirectory $desktopDirectory -PassThru
    $officeDesktopProcess.WaitForExit()
} finally {
    if (-not $officeApiProcess.HasExited) { Stop-Process -Id $officeApiProcess.Id }
}
