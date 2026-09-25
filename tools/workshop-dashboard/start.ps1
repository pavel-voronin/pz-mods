$ErrorActionPreference = 'Stop'
$dashboardPort = 8779
$dashboardUrl = "http://127.0.0.1:$dashboardPort"
try {
    $existingDashboard = Invoke-RestMethod -Uri "$dashboardUrl/api/dashboard" -TimeoutSec 2
} catch {
    $dashboardNode = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $dashboardNode) {
        $dashboardNode = Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe'
    }
    if (-not (Test-Path -LiteralPath $dashboardNode)) { throw 'Не найден Node.js 22 или новее.' }
    Start-Process -FilePath $dashboardNode -ArgumentList ('"' + (Join-Path $PSScriptRoot 'server.mjs') + '"') -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $PSScriptRoot 'server.log') -RedirectStandardError (Join-Path $PSScriptRoot 'server-error.log')
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        try { Invoke-RestMethod -Uri "$dashboardUrl/api/dashboard" -TimeoutSec 1 | Out-Null; break } catch { Start-Sleep -Milliseconds 500 }
    }
}
Start-Process $dashboardUrl
