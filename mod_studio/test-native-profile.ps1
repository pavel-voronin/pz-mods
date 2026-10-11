$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'scenario-profile.ps1')
$output=Join-Path $PSScriptRoot ('.build/native-profile-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
$native=Join-Path $env:USERPROFILE 'Zomboid'
$before=@{};foreach($file in @('options.ini','mods/default.txt')){$before[$file]=(Get-FileHash -LiteralPath (Join-Path $native $file)).Hash}
$profile=Get-ModStudioPersistentProfile -Output $output -Game 'C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid' -Roots @($PSScriptRoot) -Mode new -NativeOnly
$mods=@(Get-Content (Join-Path $profile.path 'mods/default.txt') | ForEach-Object {if($_ -match '^\s*mod\s*=\s*([^,]+),'){$Matches[1]}})
if(($mods -join ',') -ne 'ZombieBuddy,mod_studio'){throw 'Native-only profile enabled unwanted mods'}
foreach($id in $mods){if((Get-Item -LiteralPath (Join-Path $profile.path "mods/$id")).LinkType -ne 'Junction'){throw 'Native package was copied rather than linked'}}
Set-ModStudioProfileDisplay -Profile $profile -Width 1920 -Height 1200 -FullScreen
foreach($file in $before.Keys){if((Get-FileHash -LiteralPath (Join-Path $native $file)).Hash -ne $before[$file]){throw 'User settings changed'}}
Write-Output 'PASS: exactly ZombieBuddy + Mod Studio, owned package links, display overrides, unchanged user settings.'
