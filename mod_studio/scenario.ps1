[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Scenario,
    [string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string[]]$ModRoots=@(),
    [switch]$SkipBuild,
    [switch]$IsolatedProfile,
    [string]$ReuseIsolatedArtifact='',
    [switch]$PrepareOnly,
    [string]$ResumeArtifact='',
    [switch]$Mcp,
    [ValidateRange(60,7200)][int]$McpSeconds=1800,
    [ValidateSet('Java','Native')][string]$Launcher='Java',
    [ValidateSet('Z','G1')][string]$GarbageCollector='Z',
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
$persistenceMode=''
if($data.persistence){
    $persistenceMode=[string]$data.persistence.mode
    if($persistenceMode -notin @('new','resume') -or @($data.persistence.PSObject.Properties).Count -ne 1){throw 'Persistence requires only mode new or resume'}
    if($data.multiplayer -or $data.manual -or ($data.repeats -and $data.repeats -ne 1) -or $Mcp -or $Launcher -ne 'Java'){throw 'Persistent acceptance requires one owned Java single-player run'}
    if(($persistenceMode -eq 'resume') -ne [bool]$ResumeArtifact){throw 'ResumeArtifact is required only for persistence mode resume'}
}elseif($ResumeArtifact){throw 'ResumeArtifact requires persistence mode resume'}
if($ReuseIsolatedArtifact -and !$IsolatedProfile){throw 'ReuseIsolatedArtifact requires IsolatedProfile'}
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
$copy=Join-Path $output 'scenario.json'
[IO.File]::WriteAllText($copy,$text,[Text.UTF8Encoding]::new($false))
$config=Get-Content -LiteralPath (Join-Path $Game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$gcArguments=if($GarbageCollector -eq 'G1'){@('-XX:-UseZGC','-XX:+UseG1GC')}else{@('-XX:-UseG1GC','-XX:+UseZGC')}
$arguments=@($config.vmArgs)+$gcArguments+@("-javaagent:$(Join-Path $Game 'ZombieBuddy.jar')",'-Ddebug=true',"-Dmodstudio.scenario=$copy","-Dmodstudio.scenario.output=$output")
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
    $persistentProfile=Get-ModStudioPersistentProfile -Output $output -Game $Game -Roots $roots -Mode $persistenceMode -ResumeArtifact $ResumeArtifact
    $launch.nativeProfile=$persistentProfile.path;$launch.profileToken=$persistentProfile.token;$launch.persistence=$persistenceMode;$launch.resumeArtifact=$persistentProfile.previous
    $arguments+=@("-Dmodstudio.scenario.profile=$($persistentProfile.path)","-Dmodstudio.scenario.profile.token=$($persistentProfile.token)")
}
if($IsolatedProfile){
    . (Join-Path $PSScriptRoot 'scenario-profile.ps1')
    $persistentProfile=Get-ModStudioIsolatedProfile -Output $output -Game $Game -Roots $roots -ReuseArtifact $ReuseIsolatedArtifact
    $launch.nativeProfile=$persistentProfile.path;$launch.isolatedProfile=$true;$launch.reusedIsolatedArtifact=$ReuseIsolatedArtifact
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
