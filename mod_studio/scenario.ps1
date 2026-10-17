[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Scenario,
    [string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string[]]$ModRoots=@(),
    [switch]$SkipBuild,
    [switch]$IsolatedProfile,
    [switch]$MinimalMods,
    [switch]$NativeOnly,
    [switch]$NativeRender,
    [ValidateSet(0,11,13)][int]$NativeGrid=0,
    [string]$ReuseIsolatedArtifact='',
    [switch]$PrepareOnly,
    [string]$ResumeArtifact='',
    [switch]$ReuseCommonCache,
    [ValidateRange(0,7680)][int]$WindowWidth=0,
    [ValidateRange(0,4320)][int]$WindowHeight=0,
    [switch]$FullScreen,
    [switch]$Borderless,
    [switch]$Mcp,
    [ValidateRange(60,7200)][int]$McpSeconds=1800,
    [ValidateSet('Java','Native')][string]$Launcher='Java',
    [ValidateSet('Z','G1')][string]$GarbageCollector='Z',
    [ValidateRange(0,65536)][int]$JavaHeapMiB=0,
    [int]$TimeoutSeconds=600
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'game-session.ps1')
$modStudioSession=if(!$PrepareOnly){Start-ModStudioSession -Mode scenario -Source $Scenario -Checkout $PSScriptRoot}else{$null}
try {
$scenarioPath=(Resolve-Path -LiteralPath $Scenario).Path
$text=[IO.File]::ReadAllText($scenarioPath)
$data=$text | ConvertFrom-Json
if($data.schema -ne 1 -or $data.id -notmatch '^[a-z0-9_-]{1,80}$' -or !$data.spawn -or !$data.steps){throw 'Expected schema=1, id, spawn and steps.'}
if($data.steps.Count -gt 512){throw 'At most 512 steps.'}
if($JavaHeapMiB -and ($Launcher -ne 'Java' -or $JavaHeapMiB -lt 256)){throw 'JavaHeapMiB requires the Java launcher and at least 256 MiB'}
$persistenceMode=''
if($ReuseCommonCache -and !$data.persistence){throw 'Common cache reuse requires an owned persistent profile'}
if(($WindowWidth -eq 0) -ne ($WindowHeight -eq 0) -or ($WindowWidth -ne 0 -and ($WindowWidth -lt 640 -or $WindowHeight -lt 480))){throw 'Display override requires both width >= 640 and height >= 480'}
if($WindowWidth -and !$IsolatedProfile -and !$data.persistence){throw 'Display override requires an owned profile'}
if($FullScreen -and !$WindowWidth){throw 'Fullscreen override requires explicit owned display dimensions'}
if($Borderless -and (!$WindowWidth -or $FullScreen)){throw 'Borderless override requires explicit dimensions without exclusive fullscreen'}
if($data.persistence){
    $persistenceMode=[string]$data.persistence.mode
    $persistenceFields=@($data.persistence.PSObject.Properties.Name)
    if($persistenceMode -notin @('new','resume') -or @($persistenceFields | Where-Object {$_ -notin @('mode','readOnly')}).Count -gt 0 -or ($persistenceFields -contains 'readOnly') -and ($persistenceMode -ne 'resume' -or $data.persistence.readOnly -isnot [bool])){throw 'Persistence requires mode new or resume; readOnly is a resume boolean'}
    if($data.multiplayer -or ($data.repeats -and $data.repeats -ne 1) -or $Mcp -or $Launcher -ne 'Java'){throw 'Persistent acceptance requires one owned Java single-player run'}
    if(($persistenceMode -eq 'resume') -ne [bool]$ResumeArtifact){throw 'ResumeArtifact is required only for persistence mode resume'}
}elseif($ResumeArtifact){throw 'ResumeArtifact requires persistence mode resume'}
if($ReuseIsolatedArtifact -and !$IsolatedProfile){throw 'ReuseIsolatedArtifact requires IsolatedProfile'}
if($MinimalMods -and (!$IsolatedProfile -or $NativeOnly -or $ReuseIsolatedArtifact)){throw 'MinimalMods requires a fresh isolated profile without NativeOnly'}
if($NativeRender -and (!$NativeOnly -or $NativeGrid)){throw 'NativeRender requires NativeOnly with the default grid'}
if(($NativeOnly -or $NativeGrid) -and (!$NativeOnly -or !$IsolatedProfile -or $ReuseIsolatedArtifact -or $ModRoots.Count -or $data.persistence -or $data.manual -or $data.multiplayer -or $Launcher -ne 'Java')){throw 'Native baseline requires a fresh isolated native-only NoSave single-player Java profile and no additional mods'}
if($IsolatedProfile -and ($persistenceMode -or $Launcher -ne 'Java')){throw 'IsolatedProfile requires a nonpersistent Java scenario'}
if($Mcp -and $data.multiplayer){throw 'Use the single-player scenario launcher for MCP continuation.'}
if(@($data.steps | Where-Object {$_.command -like 'mcp.*'}).Count){throw 'Enable MCP with -Mcp, not a scenario command.'}
$running=Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -like 'ProjectZomboid*'}
$javaGame=Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe'" | Where-Object {$_.CommandLine -match 'zombie\.(gameStates\.MainScreenState|network\.GameServer)'}
if(!$PrepareOnly -and ($running -or $javaGame)){throw 'A Project Zomboid client or server is already running. Close it normally before a scenario launch.'}
$roots=@($PSScriptRoot)+@($ModRoots | ForEach-Object {(Resolve-Path -LiteralPath $_).Path}) | Select-Object -Unique
if(!$SkipBuild){foreach($root in $roots){& (Join-Path $root 'build.ps1') -Game $Game}}
$id=[DateTime]::UtcNow.ToString('yyyyMMdd-THHmmssZ')+'-'+[guid]::NewGuid().ToString('N')
$output=Join-Path $env:USERPROFILE "Zomboid/ModStudio/scenarios/$id"
New-Item -ItemType Directory -Path $output | Out-Null
if($NativeOnly -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.build/native-inputs.json'))){
    $inputs=Join-Path $output 'inputs';New-Item -ItemType Directory -Path $inputs | Out-Null
    foreach($name in @('native-inputs.json','native-inputs.zip')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot ".build/$name") -Destination $inputs}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Contents/mods/mod_studio/42.20.4/media/java/client/ModStudio.jar') -Destination $inputs
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Contents/mods/mod_studio/42.20.4/media/java/client/ModStudio.jar.zbs') -Destination $inputs
}
$copy=Join-Path $output 'scenario.json'
[IO.File]::WriteAllText($copy,$text,[Text.UTF8Encoding]::new($false))
$config=Get-Content -LiteralPath (Join-Path $Game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$gcArguments=if($GarbageCollector -eq 'G1'){@('-XX:-UseZGC','-XX:+UseG1GC')}else{@('-XX:-UseG1GC','-XX:+UseZGC')}
$vmArguments=@($config.vmArgs)
if($JavaHeapMiB){$vmArguments=@($vmArguments | Where-Object {$_ -notmatch '^-Xmx'})+@("-Xmx${JavaHeapMiB}m")}
$arguments=$vmArguments+$gcArguments+@("-javaagent:$(Join-Path $Game 'ZombieBuddy.jar')",'-Ddebug=true',"-Dmodstudio.scenario=$copy","-Dmodstudio.scenario.output=$output")
if($NativeOnly -and !$NativeRender){$arguments+=@('-Dmodstudio.nativeBaseline=true',"-Dmodstudio.nativeGrid=$NativeGrid", "-Dmodstudio.nativeMap=$PSScriptRoot/.build/native-map")}
if($Launcher -eq 'Native'){$arguments=$gcArguments+@('-agentlib:zbNative=policy=allow-all','-Ddebug=true',"-Dmodstudio.scenario=$copy","-Dmodstudio.scenario.output=$output")}
$mcpSession=$null
if($Mcp){
    $mcpSession=[guid]::NewGuid().ToString()
    $arguments+=@("-Dmodstudio.scenario.mcp=$mcpSession","-Dmodstudio.scenario.mcp.seconds=$McpSeconds")
    New-Item -ItemType Directory -Path (Join-Path $output 'mcp') | Out-Null
    # The scenario watchdog still owns the process throughout the continuation.
    $TimeoutSeconds+=$McpSeconds
}
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
        $arguments+=@("$prefix.commit=$commit","$prefix.dirty=$dirty","$prefix.jarSha256=$hash","$prefix.jarPath=$jar")
    }
}
$packages | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'packages.json') -Encoding utf8
@{processors=@(Get-CimInstance Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors);graphics=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM)} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'hardware.json') -Encoding utf8
foreach($entry in @(@('options.ini','game-options.ini'),@('mods/default.txt','active-mods.txt'))){
    $from=Join-Path $env:USERPROFILE ('Zomboid/'+$entry[0]);if(Test-Path -LiteralPath $from){Copy-Item -LiteralPath $from -Destination (Join-Path $output $entry[1])}
}
$launch=[ordered]@{schema=1;status='prepared';source=$scenarioPath;output=$output;createdUtc=[DateTime]::UtcNow.ToString('o');launcher=$Launcher;garbageCollector=$GarbageCollector}
$persistentProfile=$null
if($persistenceMode){
    . (Join-Path $PSScriptRoot 'scenario-profile.ps1')
    $persistentProfile=Get-ModStudioPersistentProfile -Output $output -Game $Game -Roots $roots -Mode $persistenceMode -ResumeArtifact $ResumeArtifact -ReadOnly:($data.persistence.readOnly -eq $true)
    $launch.nativeProfile=$persistentProfile.path;$launch.profileToken=$persistentProfile.token;$launch.persistence=$persistenceMode;$launch.resumeArtifact=$persistentProfile.previous
    if($ReuseCommonCache -and $persistenceMode -eq 'new'){$launch.commonCache=Connect-ModStudioCommonCache -Profile $persistentProfile}
    $arguments+=@("-Dmodstudio.scenario.profile=$($persistentProfile.path)","-Dmodstudio.scenario.profile.token=$($persistentProfile.token)")
}
if($IsolatedProfile){
    . (Join-Path $PSScriptRoot 'scenario-profile.ps1')
    $persistentProfile=if($NativeOnly -or $MinimalMods){Get-ModStudioPersistentProfile -Output $output -Game $Game -Roots $roots -Mode new -NativeOnly:$NativeOnly}else{Get-ModStudioIsolatedProfile -Output $output -Game $Game -Roots $roots -ReuseArtifact $ReuseIsolatedArtifact}
    $launch.minimalMods=[bool]$MinimalMods
    $launch.nativeOnly=[bool]$NativeOnly;$launch.nativeRender=[bool]$NativeRender;$launch.nativeGrid=$NativeGrid
    $launch.nativeProfile=$persistentProfile.path;$launch.isolatedProfile=$true;$launch.reusedIsolatedArtifact=$ReuseIsolatedArtifact
}
if($WindowWidth){
    Set-ModStudioProfileDisplay -Profile $persistentProfile -Width $WindowWidth -Height $WindowHeight -FullScreen:$FullScreen -Borderless:$Borderless
    $launch.requestedWidth=$WindowWidth;$launch.requestedHeight=$WindowHeight
    $launch.requestedFullscreen=[bool]$FullScreen
    $launch.requestedBorderless=[bool]$Borderless
    Copy-Item -LiteralPath (Join-Path $persistentProfile.path 'options.ini') -Destination (Join-Path $output 'game-options.ini') -Force
}
$launchPath=Join-Path $output 'launch.json'
$launch | ConvertTo-Json | Set-Content -LiteralPath $launchPath -Encoding utf8
Write-Output "Scenario artifact: $output"
if($PrepareOnly){return}
if($Mcp){
    $connection=@{id=$mcpSession;output=$output;mailbox=(Join-Path $output 'mcp');launcherPid=$PID;createdUtc=[DateTime]::UtcNow.ToString('o')}
    $connection | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'mcp-session.json') -Encoding utf8
    $current=Join-Path $env:USERPROFILE 'Zomboid/ModStudio/mcp-current.json'
    $temporary=$current+'.'+$mcpSession+'.tmp'
    $connection | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $current -Force
    $launch.mcpSession=$mcpSession;$launch.mcpSeconds=$McpSeconds
}
$start=[Diagnostics.ProcessStartInfo]::new()
$start.FileName=Join-Path $Game 'jre64/bin/java.exe';$start.WorkingDirectory=$Game
$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
# Hide the Java helper console; the native game window remains visible.
if($Launcher -eq 'Native'){
    $start.FileName=Join-Path $Game 'ProjectZomboid64.exe'
    foreach($arg in ($arguments+@('--','-debug'))){$start.ArgumentList.Add($arg)}
}else{
    $nativeArguments=@('-debug');if($persistentProfile){$nativeArguments+=@('-nosteam','-windowed',"-cachedir=$($persistentProfile.path)")}
    foreach($arg in ($arguments+@('-cp',($config.classpath -join ';'),'zombie.gameStates.MainScreenState')+$nativeArguments)){$start.ArgumentList.Add($arg)}
}
. (Join-Path $PSScriptRoot 'process.ps1')
if($persistentProfile){Invoke-ModStudioProcess -Start $start -Launch $launch -Output $output -TimeoutSeconds $TimeoutSeconds -ConsolePath (Join-Path $persistentProfile.path 'console.txt')}else{Invoke-ModStudioProcess -Start $start -Launch $launch -Output $output -TimeoutSeconds $TimeoutSeconds}
} finally {Stop-ModStudioSession $modStudioSession}
