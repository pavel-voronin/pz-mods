function Get-ModStudioPersistentProfile {
    param([string]$Output,[string]$Game,[string[]]$Roots,[string]$Mode,[string]$ResumeArtifact='')
    $artifactRoot=Split-Path $Output
    if($Mode -eq 'resume'){
        if($ResumeArtifact -notmatch '^[0-9]{8}-T[0-9]{6}Z-[a-f0-9]{32}$'){throw 'ResumeArtifact must be an owned scenario artifact id'}
        $previous=Join-Path $artifactRoot $ResumeArtifact
        $oldLaunch=Get-Content -LiteralPath (Join-Path $previous 'launch.json') -Raw | ConvertFrom-Json
        if($oldLaunch.status -ne 'complete' -or !$oldLaunch.exited -or $oldLaunch.exitCode -ne 0 -or $oldLaunch.forcedExit -or $oldLaunch.manualControl){throw 'Only a normally completed owned persistent artifact can resume'}
        $profile=(Resolve-Path -LiteralPath (Join-Path $previous 'native-profile')).Path
        if($oldLaunch.nativeProfile -ne $profile){throw 'Resume profile launch mismatch'}
        $owner=Get-Content -LiteralPath (Join-Path $profile 'profile-owner.json') -Raw | ConvertFrom-Json
        if($owner.schema -ne 1 -or $owner.profile -ne $profile -or $owner.token -ne $oldLaunch.profileToken){throw 'Resume profile ownership mismatch'}
        $saved=Get-Content -LiteralPath (Join-Path $profile 'native-save.json') -Raw | ConvertFrom-Json
        if(!$saved.nativeSave -or $saved.profile -ne $profile -or $saved.gameMode -ne 'Sandbox' -or $saved.world -notmatch '^[A-Za-z0-9_-]{1,128}$'){throw 'No accepted native Sandbox save to resume'}
        return @{path=$profile;token=$owner.token;previous=$ResumeArtifact}
    }
    if($Mode -ne 'new' -or $ResumeArtifact){throw 'Persistent mode new cannot resume an artifact'}
    $profile=Join-Path $Output 'native-profile'
    New-Item -ItemType Directory -Path (Join-Path $profile 'mods') | Out-Null
    $profile=(Resolve-Path -LiteralPath $profile).Path
    $sources=[ordered]@{}
    foreach($root in $Roots){
        foreach($package in Get-ChildItem -LiteralPath (Join-Path $root 'Contents/mods') -Directory){$sources[$package.Name]=$package.FullName}
    }
    $workshop=[IO.Path]::GetFullPath((Join-Path (Split-Path $Game) '../workshop/content/108600'))
    $buddy=Get-ChildItem -LiteralPath $workshop -Directory | ForEach-Object {Join-Path $_.FullName 'mods/ZombieBuddy'} | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
    if(!$buddy){throw 'ZombieBuddy native package is unavailable'}
    $sources.ZombieBuddy=$buddy
    foreach($id in $sources.Keys){
        if($id -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid native package id'}
        New-Item -ItemType Junction -Path (Join-Path $profile "mods/$id") -Target $sources[$id] | Out-Null
    }
    $mods=@('ZombieBuddy')+@($sources.Keys | Where-Object {$_ -ne 'ZombieBuddy'})
    $preset="VERSION = 1,`nmods`n{`n"+(($mods | ForEach-Object {"    mod = $_,"}) -join "`n")+"`n}`nmaps`n{`n}`n"
    [IO.File]::WriteAllText((Join-Path $profile 'mods/default.txt'),$preset)
    [IO.File]::WriteAllText((Join-Path $profile 'mods/reset-mods-42_00.txt'),'Native 42.x profile initialized by Mod Studio.')
    $terms=0
    $nativeOptions=Join-Path $env:USERPROFILE 'Zomboid/options.ini'
    if(Test-Path -LiteralPath $nativeOptions){$line=Get-Content -LiteralPath $nativeOptions | Where-Object {$_ -match '^termsOfServiceVersion='} | Select-Object -First 1;if($line){$terms=[int]($line.Split('=')[1])}}
    [IO.File]::WriteAllText((Join-Path $profile 'options.ini'),"version=8`nfullScreen=false`nborderless=false`nwidth=1280`nheight=720`nfocusloss=false`nshowSurvivalGuide=false`nframeRate=60`nuncappedFPS=false`nvsync=false`nvoiceEnable=false`nmusicVolume=0`nlanguage=EN`ntermsOfServiceVersion=$terms`nlockCursorToWindow=false`n")
    $approvals=@()
    foreach($id in $sources.Keys){foreach($jar in Get-ChildItem -LiteralPath $sources[$id] -Recurse -Filter '*.jar'){$approvals+=@{id=$id;jar_hash=(Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256).Hash.ToLowerInvariant();decision=$true;time=[DateTime]::UtcNow.ToString('o')}}}
    $approvalDirectory=Join-Path $profile 'ZombieBuddy'
    New-Item -ItemType Directory -Path $approvalDirectory | Out-Null
    @{formatVersion=2;mods=$approvals} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $approvalDirectory 'mod_approvals.json') -Encoding utf8
    $token=[guid]::NewGuid().ToString()
    @{schema=1;profile=$profile;token=$token} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profile 'profile-owner.json') -Encoding utf8
    return @{path=$profile;token=$token;previous=''}
}

# NoSave uses the same native package links as persistent/MP runs, preserving user quality.
function Get-ModStudioIsolatedProfile {
    param([string]$Output,[string]$Game,[string[]]$Roots)
    $result=Get-ModStudioPersistentProfile -Output $Output -Game $Game -Roots $Roots -Mode new
    $profile=$result.path
    $native=Join-Path $env:USERPROFILE 'Zomboid'
    Copy-Item -LiteralPath (Join-Path $native 'options.ini') -Destination (Join-Path $profile 'options.ini') -Force
    $preset=Join-Path $native 'mods/default.txt'
    $workshop=[IO.Path]::GetFullPath((Join-Path (Split-Path $Game) '../workshop/content/108600'))
    $ids=@(Get-Content -LiteralPath $preset | ForEach-Object {if($_ -match '^\s*mod\s*=\s*([A-Za-z0-9_-]+),'){$Matches[1]}})
    foreach($id in $ids){
        $target=Join-Path $profile "mods/$id"
        if(Test-Path -LiteralPath $target){continue}
        $source=Join-Path $native "mods/$id"
        if(!(Test-Path -LiteralPath $source)){
            $source=Get-ChildItem -LiteralPath (Split-Path $PSScriptRoot) -Directory | ForEach-Object {Join-Path $_.FullName "Contents/mods/$id"} | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
        }
        if(!$source -or !(Test-Path -LiteralPath $source)){
            $source=Get-ChildItem -LiteralPath $workshop -Directory | ForEach-Object {Join-Path $_.FullName "mods/$id"} | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
        }
        if(!$source){throw "Enabled native package unavailable: $id"}
        New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    }
    Copy-Item -LiteralPath $preset -Destination (Join-Path $profile 'mods/default.txt') -Force
    New-Item -ItemType Directory -Path (Join-Path $profile 'Lua') -Force | Out-Null
    $settings=Join-Path $native 'Lua/PZ3D.properties'
    if(Test-Path -LiteralPath $settings){Copy-Item -LiteralPath $settings -Destination (Join-Path $profile 'Lua/PZ3D.properties')}
    # Approval remains restricted to the hashes already accepted by the native profile.
    $approvals=Join-Path $native 'ZombieBuddy/mod_approvals.json'
    if(Test-Path -LiteralPath $approvals){
        $own=Get-Content -LiteralPath (Join-Path $profile 'ZombieBuddy/mod_approvals.json') -Raw | ConvertFrom-Json
        $old=Get-Content -LiteralPath $approvals -Raw | ConvertFrom-Json
        $own.mods=@($own.mods)+@($old.mods)
        $own | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $profile 'ZombieBuddy/mod_approvals.json') -Encoding utf8
    }
    return $result
}
