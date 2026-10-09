$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'game-session.ps1')
$root=Join-Path $PSScriptRoot ('.build/session-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
$path=Join-Path $root 'game-session.lock'
$scriptPath=Join-Path $PSScriptRoot 'game-session.ps1'
$child=Join-Path $root 'compete.ps1'
$source=@'
param($Library,$Lock,$Result)
. $Library
try{
    $session=Start-ModStudioSession -Mode competitor -Path $Lock
    Stop-ModStudioSession $session
    'acquired' | Set-Content -LiteralPath $Result
}catch{
    $_.Exception.Message | Set-Content -LiteralPath $Result
}
'@
[IO.File]::WriteAllText($child,$source)
function Compete {
    $result=Join-Path $root ([guid]::NewGuid().ToString('N')+'.txt')
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=(Get-Process -Id $PID).Path;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    foreach($arg in @('-NoProfile','-File',$child,$scriptPath,$path,$result)){$start.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($start)
    try{if(!$process.WaitForExit(10000)){$process.Kill();throw 'Lock fixture timed out'}}finally{$process.Dispose()}
    return [IO.File]::ReadAllText($result).Trim()
}
$session=Start-ModStudioSession -Mode owner -Source fixture -Path $path
try{
    Update-ModStudioSession $session -Phase loading -Artifact fixture-artifact
    $metadata=Read-ModStudioSession -Path $path
    if($metadata.mode -ne 'owner' -or $metadata.launcherPid -ne $PID -or $metadata.artifact -ne 'fixture-artifact'){throw 'Unreadable owner metadata'}
    $message=Compete
    if($message -notmatch 'locked:' -or $message -notmatch 'fixture-artifact'){throw "Concurrent writer was not rejected with owner metadata: $message"}
}finally{Stop-ModStudioSession $session}
if((Compete) -ne 'acquired'){throw 'Released metadata blocked a new owner'}
# Stale metadata left by a dead owner is recovered by opening a new OS lease.
[IO.File]::WriteAllText($path,'{"schema":1,"phase":"loading","launcherPid":2147483647,"processes":[]}')
if((Compete) -ne 'acquired'){throw 'Dead launcher metadata blocked a new owner'}
# A surviving game is protected even after the launcher lease was released.
$session=Start-ModStudioSession -Mode handoff -Path $path
Update-ModStudioSession $session -Process (Get-Process -Id $PID) -Role game
Stop-ModStudioSession $session
if((Compete) -notmatch 'owned game remains active'){throw 'Live handoff was not protected'}
# PID reuse with a different creation time must not block a new owner.
$stale=Read-ModStudioSession -Path $path;$stale.processes[0].startedUtc='2000-01-01T00:00:00.0000000Z'
[IO.File]::WriteAllText($path,($stale | ConvertTo-Json -Depth 8))
if((Compete) -ne 'acquired'){throw 'PID reuse was not recovered'}
Write-Output 'PASS: readable metadata, concurrent exclusion, release, crash recovery, live handoff and PID reuse'
