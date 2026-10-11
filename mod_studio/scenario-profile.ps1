function Connect-ModStudioCommonCache {
    param([hashtable]$Profile,[string]$Source=(Join-Path $env:USERPROFILE 'Zomboid/PZ3D/fast-track'))
    $root=(Resolve-Path -LiteralPath $Profile.path).Path
    $owner=Get-Content -LiteralPath (Join-Path $root 'profile-owner.json') -Raw | ConvertFrom-Json
    if($owner.schema -ne 1 -or $owner.profile -ne $root -or $owner.token -ne $Profile.token){throw 'Common cache profile ownership mismatch'}
    if(!(Test-Path -LiteralPath $Source -PathType Container)){throw 'Prepared common fast track cache is missing'}
    $target=(Resolve-Path -LiteralPath $Source).Path
    $destination=Join-Path $root 'PZ3D/fast-track'
    if(Test-Path -LiteralPath $destination){throw 'Owned common cache destination already exists'}
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    New-Item -ItemType Junction -Path $destination -Target $target | Out-Null
    return $target
}

function Set-ModStudioProfileDisplay {
    param([hashtable]$Profile,[ValidateRange(640,7680)][int]$Width,[ValidateRange(480,4320)][int]$Height,[switch]$FullScreen,[switch]$Borderless)
    $root=(Resolve-Path -LiteralPath $Profile.path).Path
    $owner=Get-Content -LiteralPath (Join-Path $root 'profile-owner.json') -Raw | ConvertFrom-Json
    if($owner.schema -ne 1 -or $owner.profile -ne $root -or $owner.token -ne $Profile.token){throw 'Display profile ownership mismatch'}
    $path=Join-Path $root 'options.ini';$options=[IO.File]::ReadAllText($path)
    foreach($entry in @(@('width',$Width),@('height',$Height))){
        $pattern='(?m)^'+$entry[0]+'=[^\r\n]*'
        if(![regex]::IsMatch($options,$pattern)){throw 'Display option missing'}
        $options=[regex]::Replace($options,$pattern,($entry[0]+'='+$entry[1]))
    }
    if($FullScreen){
        $options=[regex]::Replace($options,'(?m)^fullScreen=[^\r\n]*','fullScreen=true')
        $options=[regex]::Replace($options,'(?m)^borderless=[^\r\n]*','borderless=false')
    }
    if($Borderless){$options=[regex]::Replace($options,'(?m)^fullScreen=[^\r\n]*','fullScreen=false');$options=[regex]::Replace($options,'(?m)^borderless=[^\r\n]*','borderless=true')}
    [IO.File]::WriteAllText($path,$options,[Text.UTF8Encoding]::new($false))
}

function Get-ModStudioPersistentProfile {
    param([string]$Output,[string]$Game,[string[]]$Roots,[string]$Mode,[string]$ResumeArtifact='',[switch]$ReadOnly,[switch]$NativeOnly,[switch]$CaptureOnly)
    $artifactRoot=Split-Path $Output
    if($NativeOnly -and ($Mode -ne 'new' -or $ReadOnly -or $ResumeArtifact)){throw 'Native-only profiles must be fresh and disposable'}
    if($CaptureOnly -and ($NativeOnly -or $Mode -ne 'new' -or $ReadOnly -or $ResumeArtifact)){throw 'Capture-only profiles must be fresh and disposable'}
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
        if($ReadOnly){
            # Copy only native world state. Packages and common resources stay linked.
            $sourceWorld=Join-Path $profile "Saves/Sandbox/$($saved.world)"
            if(!(Test-Path -LiteralPath (Join-Path $sourceWorld 'map_ver.bin') -PathType Leaf)){throw 'Native checkpoint world is missing'}
            $copy=Get-ModStudioPersistentProfile -Output $Output -Game $Game -Roots $Roots -Mode new
            $worldDestination=Join-Path $copy.path "Saves/Sandbox/$($saved.world)"
            if(Test-Path -LiteralPath $worldDestination){throw 'Replay destination already exists'}
            New-Item -ItemType Directory -Path (Split-Path $worldDestination) -Force | Out-Null
            Copy-Item -LiteralPath $sourceWorld -Destination $worldDestination -Recurse
            foreach($file in @('options.ini','mods/default.txt','Lua/PZ3D.properties')){
                $originalSetting=Join-Path $profile $file
                if(Test-Path -LiteralPath $originalSetting){New-Item -ItemType Directory -Path (Split-Path (Join-Path $copy.path $file)) -Force | Out-Null;Copy-Item -LiteralPath $originalSetting -Destination (Join-Path $copy.path $file) -Force}
            }
            $saved.profile=$copy.path
            $saved | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $copy.path 'native-save.json') -Encoding utf8
            $sourceCache=Join-Path $profile 'PZ3D/fast-track'
            if(Test-Path -LiteralPath $sourceCache -PathType Container){Connect-ModStudioCommonCache -Profile $copy -Source $sourceCache | Out-Null}
            $copy.previous=$ResumeArtifact
            return $copy
        }
        return @{path=$profile;token=$owner.token;previous=$ResumeArtifact}
    }
    if($Mode -ne 'new' -or $ResumeArtifact){throw 'Persistent mode new cannot resume an artifact'}
    $profile=Join-Path $Output 'native-profile'
    New-Item -ItemType Directory -Path (Join-Path $profile 'mods') | Out-Null
    $profile=(Resolve-Path -LiteralPath $profile).Path
    $sources=[ordered]@{}
    foreach($root in $Roots){
        foreach($package in Get-ChildItem -LiteralPath (Join-Path $root 'Contents/mods') -Directory){if((!$NativeOnly -and !$CaptureOnly) -or $package.Name -eq 'mod_studio' -or ($CaptureOnly -and $package.Name -eq 'pz3d')){$sources[$package.Name]=$package.FullName}}
    }
    if($NativeOnly -and !$sources.Contains('mod_studio')){throw 'Native-only profile requires Mod Studio'}
    if($CaptureOnly -and (!$sources.Contains('mod_studio') -or !$sources.Contains('pz3d'))){throw 'Capture-only profile requires Mod Studio and pz3d'}
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
    param([string]$Output,[string]$Game,[string[]]$Roots,[string]$ReuseArtifact='')
    if($ReuseArtifact){
        if($ReuseArtifact -notmatch '^[0-9]{8}-T[0-9]{6}Z-[a-f0-9]{32}$'){throw 'ReuseArtifact must identify an owned isolated artifact'}
        $previous=Join-Path (Split-Path $Output) $ReuseArtifact
        $launch=Get-Content -LiteralPath (Join-Path $previous 'launch.json') -Raw | ConvertFrom-Json
        if(!$launch.isolatedProfile -or !$launch.exited -or $launch.exitCode -ne 0 -or $launch.forcedExit -or $launch.manualControl){throw 'Reuse requires a normally exited isolated NoSave process'}
        $profile=(Resolve-Path -LiteralPath $launch.nativeProfile).Path
        $expected=[IO.Path]::GetFullPath((Join-Path $previous 'native-profile'))
        if($profile -ne $expected){throw 'Reused profile must belong to this artifact'}
        $owner=Get-Content -LiteralPath (Join-Path $profile 'profile-owner.json') -Raw | ConvertFrom-Json
        if($owner.schema -ne 1 -or $owner.profile -ne $profile -or !$owner.token){throw 'Isolated profile ownership mismatch'}
        foreach($root in $Roots){foreach($package in Get-ChildItem -LiteralPath (Join-Path $root 'Contents/mods') -Directory){
            $link=Get-Item -LiteralPath (Join-Path $profile "mods/$($package.Name)")
            if($link.LinkType -ne 'Junction' -or $link.Target -ne $package.FullName){throw 'Reused package checkout mismatch'}
        }}
        # Keep old console evidence before the native logger replaces it.
        if(!(Test-Path -LiteralPath (Join-Path $previous 'console.txt'))){throw 'Previous console evidence is missing'}
        $approvalPath=Join-Path $profile 'ZombieBuddy/mod_approvals.json'
        $approvals=Get-Content -LiteralPath $approvalPath -Raw | ConvertFrom-Json
        foreach($root in $Roots){foreach($info in Get-ChildItem -LiteralPath (Join-Path $root 'Contents/mods') -Recurse -Filter mod.info){
            $fields=@{};foreach($line in Get-Content -LiteralPath $info.FullName){if($line -match '^([^=]+)=(.*)$'){$fields[$Matches[1]]=$Matches[2]}}
            if($fields.javaJarFile){$jar=Join-Path $info.DirectoryName $fields.javaJarFile;$approvals.mods=@($approvals.mods)+@(@{id=$fields.id;jar_hash=(Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash.ToLowerInvariant();decision=$true;time=[DateTime]::UtcNow.ToString('o')})}
        }}
        $approvals | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $approvalPath -Encoding utf8
        return @{path=$profile;token=$owner.token;previous=$ReuseArtifact}
    }
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
