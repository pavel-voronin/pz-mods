[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Scenario,
    [string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string[]]$ModRoots=@(),
    [switch]$SkipBuild,
    [switch]$PrepareOnly,
    [ValidateSet('Java','Native')][string]$Launcher='Java',
    [int]$TimeoutSeconds=600
)
$ErrorActionPreference='Stop'
$scenarioPath=(Resolve-Path -LiteralPath $Scenario).Path
$text=[IO.File]::ReadAllText($scenarioPath)
$data=$text | ConvertFrom-Json
if($data.schema -ne 1 -or $data.id -notmatch '^[a-z0-9_-]{1,80}$' -or !$data.spawn -or !$data.steps){throw 'Expected schema=1, id, spawn and steps.'}
if($data.steps.Count -gt 512){throw 'At most 512 steps.'}
$running=Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -like 'ProjectZomboid*'}
$javaGame=Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe'" | Where-Object {$_.CommandLine -match 'zombie\.(gameStates\.MainScreenState|network\.GameServer)'}
if(!$PrepareOnly -and ($running -or $javaGame)){throw 'A Project Zomboid client or server is already running. Close it normally before a scenario launch.'}
$roots=@($PSScriptRoot)+@($ModRoots | ForEach-Object {(Resolve-Path -LiteralPath $_).Path}) | Select-Object -Unique
if(!$SkipBuild){foreach($root in $roots){& (Join-Path $root 'build.ps1') -Game $Game}}
$id=[DateTime]::UtcNow.ToString('yyyyMMdd-THHmmssZ')+'-'+[guid]::NewGuid().ToString('N')
$output=Join-Path $env:USERPROFILE "Zomboid/ModStudio/scenarios/$id"
New-Item -ItemType Directory -Path $output | Out-Null
$copy=Join-Path $output 'scenario.json'
[IO.File]::WriteAllText($copy,$text,[Text.UTF8Encoding]::new($false))
$config=Get-Content -LiteralPath (Join-Path $Game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$arguments=@($config.vmArgs)+@('-XX:+UseZGC',"-javaagent:$(Join-Path $Game 'ZombieBuddy.jar')",'-Ddebug=true',"-Dmodstudio.scenario=$copy","-Dmodstudio.scenario.output=$output")
if($Launcher -eq 'Native'){$arguments=@('-XX:+UseZGC','-agentlib:zbNative=policy=allow-all','-Ddebug=true',"-Dmodstudio.scenario=$copy","-Dmodstudio.scenario.output=$output")}
$packages=@()
foreach($root in $roots){
    $commit=git -C $root rev-parse HEAD
    $dirty=@(git -C $root status --porcelain -- .).Count -gt 0
    foreach($info in Get-ChildItem -LiteralPath (Join-Path $root 'Contents/mods') -Recurse -Filter mod.info){
        $fields=@{};foreach($line in Get-Content -LiteralPath $info.FullName){if($line -match '^([^=]+)=(.*)$'){$fields[$Matches[1]]=$Matches[2]}}
        if(!$fields.javaJarFile){continue}
        $jar=Join-Path $info.DirectoryName $fields.javaJarFile
        $hash=(Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash.ToLowerInvariant()
        $packages+=@{id=$fields.id;jar=$jar;sha256=$hash;commit=$commit;dirty=$dirty}
        $prefix="-Dmodstudio.scenario.$($fields.id)"
        $arguments+=@("$prefix.commit=$commit","$prefix.dirty=$dirty","$prefix.jarSha256=$hash")
    }
}
$packages | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'packages.json') -Encoding utf8
@{processors=@(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors);graphics=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'hardware.json') -Encoding utf8
foreach($entry in @(@('options.ini','game-options.ini'),@('mods/default.txt','active-mods.txt'))){
    $from=Join-Path $env:USERPROFILE ('Zomboid/'+$entry[0]);if(Test-Path -LiteralPath $from){Copy-Item -LiteralPath $from -Destination (Join-Path $output $entry[1])}
}
$launch=[ordered]@{schema=1;status='prepared';source=$scenarioPath;output=$output;createdUtc=[DateTime]::UtcNow.ToString('o');launcher=$Launcher}
$launchPath=Join-Path $output 'launch.json'
$launch | ConvertTo-Json | Set-Content -LiteralPath $launchPath -Encoding utf8
Write-Output "Scenario artifact: $output"
if($PrepareOnly){return}
$start=[Diagnostics.ProcessStartInfo]::new()
$start.FileName=Join-Path $Game 'jre64/bin/java.exe';$start.WorkingDirectory=$Game
$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
# Hide the Java helper console; the native game window remains visible.
if($Launcher -eq 'Native'){
    $start.FileName=Join-Path $Game 'ProjectZomboid64.exe'
    foreach($arg in ($arguments+@('--','-debug'))){$start.ArgumentList.Add($arg)}
}else{
    foreach($arg in ($arguments+@('-cp',($config.classpath -join ';'),'zombie.gameStates.MainScreenState','-debug'))){$start.ArgumentList.Add($arg)}
}
. (Join-Path $PSScriptRoot 'process.ps1')
Invoke-ModStudioProcess -Start $start -Launch $launch -Output $output -TimeoutSeconds $TimeoutSeconds
