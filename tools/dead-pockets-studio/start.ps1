param(
    [string]$PythonPath = (Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe')
)

$ErrorActionPreference = 'Stop'
$studioRoot = $PSScriptRoot
try {
    $studioResponse = Invoke-WebRequest -Uri 'http://127.0.0.1:8769/catalog.json' -TimeoutSec 2 -UseBasicParsing
    if ($studioResponse.StatusCode -eq 200) {
        Write-Output 'http://127.0.0.1:8769/'
        return
    }
} catch { }
Start-Process -FilePath $PythonPath -ArgumentList @('server.py') -WorkingDirectory $studioRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $studioRoot 'server.stdout.log') -RedirectStandardError (Join-Path $studioRoot 'server.stderr.log')
Write-Output 'http://127.0.0.1:8769/'
