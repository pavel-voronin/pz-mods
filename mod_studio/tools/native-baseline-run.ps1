[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Scenario,[ValidateSet(0,11,13)][int]$Grid=0,[int]$TimeoutSeconds=1400)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$textures=Join-Path $root 'Contents/mods/mod_studio/common/media/textures'
New-Item -ItemType Directory -Path $textures -Force | Out-Null
foreach($mapName in @('world','city','rural')){Copy-Item -LiteralPath (Join-Path $root ".build/native-map/$mapName.png") -Destination (Join-Path $textures "modstudio-native-baseline-$mapName.png")}
if(Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe' OR Name = 'ProjectZomboid64.exe'"){
    Write-Output 'Waiting for a free game / Java measurement window.'
    do {Start-Sleep -Seconds 2;$busy=Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe' OR Name = 'ProjectZomboid64.exe'"} while($busy)
}
$output=Join-Path $root ('.build/native-system-'+[DateTime]::UtcNow.ToString('yyyyMMdd-THHmmssZ'))
New-Item -ItemType Directory -Path $output | Out-Null
$stop=Join-Path $output 'stop'
$job=Start-Job -FilePath (Join-Path $PSScriptRoot 'native-baseline-monitor.ps1') -ArgumentList $output,$stop
$baselineRunState=@{artifact=''}
try {
    Write-Output "System telemetry: $output"
    & (Join-Path $root 'scenario.ps1') -Scenario $Scenario -SkipBuild -IsolatedProfile -NativeOnly -NativeGrid $Grid -WindowWidth 1920 -WindowHeight 1200 -FullScreen -TimeoutSeconds $TimeoutSeconds | ForEach-Object {if($_ -match '^Scenario artifact: (.+)$'){$baselineRunState.artifact=$Matches[1]};Write-Output $_}
}finally{
    [IO.File]::WriteAllText($stop,'complete')
    $job | Wait-Job -Timeout 10 | Out-Null
    Receive-Job $job
    Remove-Job $job
    if($baselineRunState.artifact -and (Test-Path -LiteralPath (Join-Path $output 'system.jsonl'))){Copy-Item -LiteralPath (Join-Path $output 'system.jsonl') -Destination (Join-Path $baselineRunState.artifact 'system.jsonl')}
}
