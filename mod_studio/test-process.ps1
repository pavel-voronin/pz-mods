$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'process.ps1')
$root=Join-Path $PSScriptRoot ('.build/process-test-'+[guid]::NewGuid().ToString('N'))
foreach($case in @('complete','locked-result','timeout','invalid-result','interactive')){
    $output=Join-Path $root $case
    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $child=Join-Path $output 'child.ps1'
    $code=switch($case){
        'complete' {"'{`"status`":`"complete`",`"reason`":`"fixture`"}' | Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'scenario-result.json')"}
        'locked-result' {@'
$lockedResult=Join-Path $PSScriptRoot 'scenario-result.json'
$handle=[IO.File]::Open($lockedResult,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
$writer=[IO.StreamWriter]::new($handle,[Text.UTF8Encoding]::new($false))
try {$writer.Write('{"status":"complete","reason":"locked fixture"}');$writer.Flush();Start-Sleep -Milliseconds 1200}
finally {$writer.Dispose()}
Start-Sleep -Milliseconds 350
'@}
        'interactive' {"'{`"status`":`"interactive`",`"reason`":`"manual fixture`"}' | Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'scenario-result.json'); Start-Sleep -Seconds 120"}
        'timeout' {'Start-Sleep -Seconds 120'}
        'invalid-result' {"'invalid json' | Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'scenario-result.json'); Start-Sleep -Seconds 120"}
    }
    [IO.File]::WriteAllText($child,$code)
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=(Get-Process -Id $PID).Path
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($a in @('-NoProfile','-File',$child)){$start.ArgumentList.Add($a)}
    $launch=[ordered]@{status='prepared'};$failed=$false
    try {Invoke-ModStudioProcess -Start $start -Launch $launch -Output $output -TimeoutSeconds $(if($case -eq 'locked-result'){5}else{2})}
    catch {$failed=$true}
    $saved=Get-Content -LiteralPath (Join-Path $output 'launch.json') -Raw | ConvertFrom-Json
    if($case -eq 'interactive'){
        try {
            if($failed -or $saved.exited -or !$saved.manualControl -or !(Get-Process -Id $saved.pid -ErrorAction SilentlyContinue)){throw 'Manual handoff did not leave its child alive'}
            Write-Output 'PASS: interactive handoff detaches and preserves owned process'
        } finally {Stop-Process -Id $saved.pid -ErrorAction SilentlyContinue}
        continue
    }
    if(!$saved.exited -or (Get-Process -Id $saved.pid -ErrorAction SilentlyContinue)){throw "$case left its child process alive"}
    if(($case -in @('complete','locked-result')) -eq $failed){throw "$case returned an unexpected outcome"}
    if($case -notin @('complete','locked-result') -and !$saved.forcedExit){throw "$case did not exercise cleanup"}
    Write-Output "PASS: $case, owned process exited"
}
