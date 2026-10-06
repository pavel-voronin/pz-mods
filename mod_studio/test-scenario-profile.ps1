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
