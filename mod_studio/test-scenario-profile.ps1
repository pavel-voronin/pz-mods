param([string]$PZ3D=(Join-Path (Split-Path $PSScriptRoot) 'pz3d'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scenario-profile.ps1')
$root=Join-Path $PSScriptRoot ('.build/profile-test-'+[guid]::NewGuid().ToString('N'))
$id='20261007-T000000Z-00000000000000000000000000000000'
$output=Join-Path $root $id
$profile=Join-Path $output 'native-profile'
New-Item -ItemType Directory -Path $profile | Out-Null
$profile=(Resolve-Path -LiteralPath $profile).Path
@{schema=1;profile=$profile;token='owner'} | ConvertTo-Json | Set-Content (Join-Path $profile 'profile-owner.json')
@{profile=$profile;nativeSave=$true;gameMode='Sandbox';world='native_world'} | ConvertTo-Json | Set-Content (Join-Path $profile 'native-save.json')
$launch=@{status='complete';exited=$true;exitCode=0;nativeProfile=$profile;profileToken='owner';forcedExit=$false;manualControl=$false}
$launch | ConvertTo-Json | Set-Content (Join-Path $output 'launch.json')
$next=Join-Path $root '20261007-T000001Z-00000000000000000000000000000001'
New-Item -ItemType Directory -Path $next | Out-Null
$result=Get-ModStudioPersistentProfile -Output $next -Mode resume -ResumeArtifact $id
if($result.path -ne $profile -or $result.token -ne 'owner'){throw 'Owned profile resume failed'}
foreach($field in @('forcedExit','manualControl','profileToken','status','exitCode')){
    $original=$launch[$field];$launch[$field]=switch($field){'profileToken' {'other'};'status' {'failed'};'exitCode' {1};default {$true}}
    $launch | ConvertTo-Json | Set-Content (Join-Path $output 'launch.json')
    $rejected=$false
    try {Get-ModStudioPersistentProfile -Output $next -Mode resume -ResumeArtifact $id | Out-Null}catch{$rejected=$true}
    if(!$rejected){throw "Rejected profile was resumed: $field"}
    $launch[$field]=$original
}
foreach($invalid in @('../user','native-profile','')){
    $rejected=$false;try{Get-ModStudioPersistentProfile -Output $next -Mode resume -ResumeArtifact $invalid | Out-Null}catch{$rejected=$true}
    if(!$rejected){throw 'Unowned artifact path accepted'}
}
Write-Output 'PASS: owned profile resume, failed process rejection and artifact identity bounds.'

$isolatedId='20261007-T000002Z-00000000000000000000000000000002'
$isolatedOutput=Join-Path $root $isolatedId
New-Item -ItemType Directory -Path $isolatedOutput | Out-Null
$game='C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid'
$modRoot=$PZ3D
$isolated=Get-ModStudioIsolatedProfile -Output $isolatedOutput -Game $game -Roots @($PSScriptRoot,$modRoot)
$native=Join-Path $env:USERPROFILE 'Zomboid'
foreach($file in @('options.ini','mods/default.txt','Lua/PZ3D.properties','Lua/keys.ini','Lua/keysB42.ini')){
    $original=Join-Path $native $file
    if(Test-Path -LiteralPath $original){if((Get-FileHash -LiteralPath $original).Hash -ne (Get-FileHash -LiteralPath (Join-Path $isolated.path $file)).Hash){throw "Isolated profile changed native settings: $file"}}
}
$link=Get-Item -LiteralPath (Join-Path $isolated.path 'mods/pz3d')
if($link.LinkType -ne 'Junction' -or $link.Target -ne (Join-Path $modRoot 'Contents/mods/pz3d')){throw 'Isolated native package is not linked to the requested checkout'}
Write-Output 'PASS: isolated NoSave package links, active mod preset, exact resolution and client preferences.'

$isolatedLaunch=@{isolatedProfile=$true;nativeProfile=$isolated.path;exited=$true;exitCode=0;manualControl=$false;forcedExit=$false}
$isolatedLaunch | ConvertTo-Json | Set-Content (Join-Path $isolatedOutput 'launch.json')
[IO.File]::WriteAllText((Join-Path $isolatedOutput 'console.txt'),'previous evidence')
$reused=Get-ModStudioIsolatedProfile -Output $next -Game $game -Roots @($PSScriptRoot,$modRoot) -ReuseArtifact $isolatedId
if($reused.path -ne $isolated.path){throw 'Isolated cache/profile was not reused'}
$isolatedLaunch.manualControl=$true
$isolatedLaunch | ConvertTo-Json | Set-Content (Join-Path $isolatedOutput 'launch.json')
$rejected=$false;try{Get-ModStudioIsolatedProfile -Output $next -Game $game -Roots @($PSScriptRoot,$modRoot) -ReuseArtifact $isolatedId | Out-Null}catch{$rejected=$true}
if(!$rejected){throw 'Live/manual isolated profile was accepted'}
Write-Output 'PASS: owned NoSave profile reuse, preserved console evidence and manual-session rejection.'

$commonFixture=Join-Path $root 'prepared-common'
New-Item -ItemType Directory -Path $commonFixture | Out-Null
[IO.File]::WriteAllText((Join-Path $commonFixture 'marker'),'prepared resource cache')
$badProfile=@{path=$isolated.path;token='incorrect'}
$rejected=$false
try {Connect-ModStudioCommonCache -Profile $badProfile -Source $commonFixture | Out-Null}catch{$rejected=$true}
if(!$rejected){throw 'Wrong common cache owner accepted'}
$connected=Connect-ModStudioCommonCache -Profile $isolated -Source $commonFixture
$commonLink=Get-Item -LiteralPath (Join-Path $isolated.path 'PZ3D/fast-track')
if($commonLink.LinkType -ne 'Junction' -or $commonLink.Target -ne $connected -or [IO.File]::ReadAllText((Join-Path $connected 'marker')) -ne 'prepared resource cache'){throw 'Common cache was copied, changed or linked incorrectly'}
$rejected=$false
try {Connect-ModStudioCommonCache -Profile $isolated -Source $commonFixture | Out-Null}catch{$rejected=$true}
if(!$rejected){throw 'Existing common cache was replaced'}
Write-Output 'PASS: prepared common cache reuse, owner validation and existing-target preservation.'

$launch | ConvertTo-Json | Set-Content (Join-Path $output 'launch.json')
$fixtureWorld=Join-Path $profile 'Saves/Sandbox/native_world'
New-Item -ItemType Directory -Path $fixtureWorld -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $fixtureWorld 'map_ver.bin'),'world version')
[IO.File]::WriteAllText((Join-Path $fixtureWorld 'state.bin'),'original state')
Connect-ModStudioCommonCache -Profile @{path=$profile;token='owner'} -Source $commonFixture | Out-Null
$replayOutput=Join-Path $root '20261007-T000003Z-00000000000000000000000000000003'
New-Item -ItemType Directory -Path $replayOutput | Out-Null
$replay=Get-ModStudioPersistentProfile -Output $replayOutput -Game $game -Roots @($PSScriptRoot,$modRoot) -Mode resume -ResumeArtifact $id -ReadOnly
$replayWorld=Join-Path $replay.path 'Saves/Sandbox/native_world'
if($replay.path -eq $profile -or $replay.previous -ne $id -or [IO.File]::ReadAllText((Join-Path $replayWorld 'state.bin')) -ne 'original state'){throw 'Replay did not copy the original native checkpoint'}
[IO.File]::WriteAllText((Join-Path $replayWorld 'state.bin'),'changed replay')
if([IO.File]::ReadAllText((Join-Path $fixtureWorld 'state.bin')) -ne 'original state'){throw 'Replay changed the original checkpoint'}
$replaySaved=Get-Content (Join-Path $replay.path 'native-save.json') -Raw | ConvertFrom-Json
if($replaySaved.profile -ne $replay.path -or (Get-Item (Join-Path $replay.path 'mods/pz3d')).LinkType -ne 'Junction' -or (Get-Item (Join-Path $replay.path 'PZ3D/fast-track')).LinkType -ne 'Junction'){throw 'Replay copied packages or lost native ownership/common cache'}
Write-Output 'PASS: immutable checkpoint replay, native world copy, linked packages and shared prepared common cache.'

$originalDisplayOptions=[IO.File]::ReadAllText((Join-Path $replay.path 'options.ini'))
$nativeDisplayHash=(Get-FileHash -LiteralPath (Join-Path $native 'options.ini')).Hash
Set-ModStudioProfileDisplay -Profile $replay -Width 1920 -Height 1200
$displayOptions=[IO.File]::ReadAllText((Join-Path $replay.path 'options.ini'))
if($displayOptions -notmatch '(?m)^width=1920\r?$' -or $displayOptions -notmatch '(?m)^height=1200\r?$'){throw 'Owned display override was not applied'}
if(($displayOptions -replace '(?m)^(width|height)=[^\r\n]*','display=removed') -ne ($originalDisplayOptions -replace '(?m)^(width|height)=[^\r\n]*','display=removed')){throw 'Display override changed other settings'}
if((Get-FileHash -LiteralPath (Join-Path $native 'options.ini')).Hash -ne $nativeDisplayHash){throw 'Owned display override changed user options'}
$rejected=$false
try{Set-ModStudioProfileDisplay -Profile @{path=$replay.path;token='wrong'} -Width 1920 -Height 1200}catch{$rejected=$true}
if(!$rejected){throw 'Display override accepted an unowned profile'}
Write-Output 'PASS: explicit owned display dimensions, unrelated preferences and user profile preservation, owner rejection.'
Set-ModStudioProfileDisplay -Profile $replay -Width 1920 -Height 1200 -FullScreen
$fullDisplayOptions=[IO.File]::ReadAllText((Join-Path $replay.path 'options.ini'))
if($fullDisplayOptions -notmatch '(?m)^fullScreen=true\r?$' -or $fullDisplayOptions -notmatch '(?m)^borderless=false\r?$'){throw 'Native fullscreen display override was not applied'}
Write-Output 'PASS: native fullscreen prevents decorated-window sizing from reducing benchmark dimensions.'
Set-ModStudioProfileDisplay -Profile $replay -Width 1920 -Height 1200 -Borderless
$borderlessOptions=[IO.File]::ReadAllText((Join-Path $replay.path 'options.ini'))
if($borderlessOptions -notmatch '(?m)^fullScreen=false\r?$' -or $borderlessOptions -notmatch '(?m)^borderless=true\r?$'){throw 'Owned borderless override failed'}
Set-ModStudioProfileDisplay -Profile $replay -Width 1920 -Height 1200 -Borderless
$borderlessOptions=[IO.File]::ReadAllText((Join-Path $replay.path 'options.ini'))
if($borderlessOptions -notmatch '(?m)^borderless=true\r?$' -or $borderlessOptions -notmatch '(?m)^fullScreen=false\r?$'){throw 'Borderless display override failed'}
if((Get-FileHash -LiteralPath (Join-Path $native 'options.ini')).Hash -ne $nativeDisplayHash){throw 'Owned borderless fixture changed user options'}
Write-Output 'PASS: owned borderless dimensions and preserved user options.'

$bindingSource=Join-Path $root 'binding-source'
$bindingTarget=Join-Path $root 'binding-target'
New-Item -ItemType Directory -Path (Join-Path $bindingSource 'Lua') -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $bindingSource 'Lua/keysB42.ini'),[byte[]]@(0x41,0x3D,0x39,0x0A))
Copy-ModStudioKeyBindings -Destination $bindingTarget -Source $bindingSource
if((Get-FileHash (Join-Path $bindingSource 'Lua/keysB42.ini')).Hash -ne (Get-FileHash (Join-Path $bindingTarget 'Lua/keysB42.ini')).Hash){throw 'Key bindings were not copied exactly'}
[IO.File]::WriteAllText((Join-Path $bindingTarget 'Lua/keysB42.ini'),'local edit')
Copy-ModStudioKeyBindings -Destination $bindingTarget -Source $bindingSource
if([IO.File]::ReadAllText((Join-Path $bindingTarget 'Lua/keysB42.ini')) -ne "A=9`n"){throw 'Reused profile did not refresh native key bindings'}
if(Test-Path (Join-Path $bindingTarget 'Lua/keys.ini')){throw 'Missing native legacy bindings were invented'}
Write-Output 'PASS: independent byte-exact native key bindings, missing legacy file and reused-profile refresh.'
