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
$modRoot=Join-Path (Split-Path $PSScriptRoot) 'pz3d'
$isolated=Get-ModStudioIsolatedProfile -Output $isolatedOutput -Game $game -Roots @($PSScriptRoot,$modRoot)
$native=Join-Path $env:USERPROFILE 'Zomboid'
foreach($file in @('options.ini','mods/default.txt','Lua/PZ3D.properties')){
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
