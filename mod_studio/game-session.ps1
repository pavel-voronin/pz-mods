# One OS-held writer lease shared by every checkout and external game launcher.
function Read-ModStudioSession {
    param([string]$Path=(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid/ModStudio/game-session.lock'))
    for($attempt=0;$attempt -lt 5;$attempt++){
        try{
            $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $reader=[IO.StreamReader]::new($stream)
            try{return $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop}finally{$reader.Dispose()}
        }catch [IO.FileNotFoundException]{return $null}
        catch {if($attempt -eq 4){return $null};Start-Sleep -Milliseconds 10}
    }
}
function Write-ModStudioSession {
    param($Session)
    $Session.data.updatedUtc=[DateTime]::UtcNow.ToString('o')
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Session.data | ConvertTo-Json -Depth 8))
    $Session.handle.Position=0;$Session.handle.SetLength(0);$Session.handle.Write($bytes,0,$bytes.Length);$Session.handle.Flush($true)
}
function Restore-ModStudioMenuSession {
    param($Metadata,[string]$Cache=(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'))
    if(!$Metadata -or $Metadata.mode -notin @('menu','startup-benchmark') -or !$Metadata.artifact){return}
    $base=[IO.Path]::GetFullPath((Join-Path $Cache 'ModStudio/scenarios'))
    $artifact=[IO.Path]::GetFullPath([string]$Metadata.artifact)
    if([IO.Path]::GetDirectoryName($artifact) -ne $base){return}
    $name=[IO.Path]::GetFileName($artifact)
    if($name -notmatch '^\d{8}-T\d{6}Z-([a-f0-9]{32})$'){return}
    $token=$Matches[1]
    $active=Join-Path $Cache 'mods/default.txt'
    $provided=Join-Path $artifact 'active-mods.txt'
    $before=Join-Path $artifact 'active-mods-before.txt'
    if((Test-Path -LiteralPath $active) -and (Test-Path -LiteralPath $provided) -and (Get-FileHash -LiteralPath $active).Hash -eq (Get-FileHash -LiteralPath $provided).Hash){
        if(Test-Path -LiteralPath $before){[IO.File]::WriteAllBytes($active,[IO.File]::ReadAllBytes($before))}
        else{Remove-Item -LiteralPath $active}
    }
    $request=Join-Path $Cache 'Lua/ModStudio/menu-request.txt'
    if((Test-Path -LiteralPath $request) -and (Get-Content -LiteralPath $request -TotalCount 1) -eq $token){Remove-Item -LiteralPath $request}
}
function Start-ModStudioSession {
    param([Parameter(Mandatory)][string]$Mode,[string]$Source='',[string]$Checkout=$PSScriptRoot,
        [string]$Path=(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid/ModStudio/game-session.lock'))
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    try{$handle=[IO.File]::Open($Path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)}
    catch [IO.IOException]{
        $owner=Read-ModStudioSession -Path $Path
        $detail=if($owner){$owner | ConvertTo-Json -Depth 8 -Compress}else{'Owner metadata is being updated'}
        throw "Mod Studio game session is locked: $Path | $detail"
    }
    try{
        # A crashed launcher or manual handoff may leave a live game after the lease is released.
        $old=Read-ModStudioSession -Path $Path
        foreach($entry in @($old.processes)){
            if(!$entry -or !$entry.pid -or !$entry.startedUtc){continue}
            $process=Get-Process -Id $entry.pid -ErrorAction SilentlyContinue
            $sameStart=$false
            try{$sameStart=$process -and $process.StartTime.ToUniversalTime().Ticks -eq ([DateTimeOffset]$entry.startedUtc).UtcTicks}catch{}
            if($process -and !$process.HasExited -and $sameStart){
                throw "Mod Studio owned game remains active: $Path | $($old | ConvertTo-Json -Depth 8 -Compress)"
            }
        }
        Restore-ModStudioMenuSession $old
        $session=@{path=$Path;handle=$handle;data=[ordered]@{
            schema=1;token=[guid]::NewGuid().ToString('N');mode=$Mode;source=$Source;checkout=$Checkout
            launcherPid=$PID;launcherStartedUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
            acquiredUtc=[DateTime]::UtcNow.ToString('o');updatedUtc='';phase='preparing';artifact='';processes=@()
        }}
        Write-ModStudioSession $session
        return $session
    }catch{$handle.Dispose();throw}
}
function Update-ModStudioSession {
    param($Session,[string]$Phase,[string]$Artifact,[Diagnostics.Process]$Process,[string]$Role='game')
    if(!$Session){return}
    $changed=$false
    if($Phase -and $Session.data.phase -ne $Phase){$Session.data.phase=$Phase;$changed=$true}
    if($Artifact -and $Session.data.artifact -ne $Artifact){$Session.data.artifact=$Artifact;$changed=$true}
    if($Process){$Session.data.processes+=@{pid=$Process.Id;role=$Role;startedUtc=$Process.StartTime.ToUniversalTime().ToString('o')};$changed=$true}
    if($changed){Write-ModStudioSession $Session}
}
function Stop-ModStudioSession {
    param($Session)
    if(!$Session){return}
    try{
        $Session.data.phase='released';$Session.data.releasedUtc=[DateTime]::UtcNow.ToString('o')
        Write-ModStudioSession $Session
    }finally{$Session.handle.Dispose()}
}

function Test-ModStudioLoaderOwner {
    param([string]$ConsoleText,[string]$StdoutText,[string]$ExpectedOwner)
    $evidence=$ConsoleText+"`n"+$StdoutText
    $owners=[regex]::Matches($evidence,'owner=(Pz3dLoader|ZombieBuddy)(?:[\r\n]|$)')
    if($owners.Count){return @($owners | Where-Object {$_.Groups[1].Value -ne $ExpectedOwner}).Count -eq 0}
    if($ExpectedOwner -ne 'ZombieBuddy'){return $false}
    $entry=$evidence -match '\[ZB\] class com\.pavelvoronin\.pz3d\.entry\.Main: method main\(\) invoked successfully'
    $signed=$evidence -match '\[ZB\] ZBS verification valid for [^\r\n]*[\\/]mods[\\/]pz3d[\\/][^\r\n]*[\\/]PZ3D[^\r\n]*\.jar:'
    $started=$evidence -match '\[pz3d\] Java prototype [^\r\n]+ loaded; patch targets resolved;'
    return $entry -and $signed -and $started
}
