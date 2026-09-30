$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'process.ps1')
$root=Join-Path $PSScriptRoot ('.build/process-test-'+[guid]::NewGuid().ToString('N'))
foreach($case in @('complete','timeout','invalid-result')){
    $output=Join-Path $root $case
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $child=Join-Path $output 'child.ps1'
    $code=switch($case){
        'complete' {"'{`"status`":`"complete`",`"reason`":`"fixture`"}' | Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'scenario-result.json')"}
        'timeout' {'Start-Sleep -Seconds 120'}
        'invalid-result' {"'invalid json' | Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'scenario-result.json'); Start-Sleep -Seconds 120"}
    }
    [IO.File]::WriteAllText($child,$code)
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=(Get-Process -Id $PID).Path
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($a in @('-NoProfile','-File',$child)){$start.ArgumentList.Add($a)}
    $launch=[ordered]@{status='prepared'};$failed=$false
    try {Invoke-ModStudioProcess -Start $start -Launch $launch -Output $output -TimeoutSeconds 2}
    catch {$failed=$true}
    $saved=Get-Content -LiteralPath (Join-Path $output 'launch.json') -Raw | ConvertFrom-Json
    if(!$saved.exited -or (Get-Process -Id $saved.pid -ErrorAction SilentlyContinue)){throw "$case left its child process alive"}
    if(($case -eq 'complete') -eq $failed){throw "$case returned an unexpected outcome"}
    if($case -ne 'complete' -and !$saved.forcedExit){throw "$case did not exercise cleanup"}
    Write-Output "PASS: $case, owned process exited"
}
