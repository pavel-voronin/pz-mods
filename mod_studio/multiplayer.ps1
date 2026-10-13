[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Scenario,
    [string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string[]]$ModRoots=@(),
    [string]$OutputRoot=(Join-Path $env:USERPROFILE 'Zomboid/ModStudio/multiplayer'),
    [ValidateRange(1024,65534)][int]$Port=16371,
    [ValidateRange(60,7200)][int]$TimeoutSeconds=600,
    [ValidateSet('zombieBuddy','pz3d')][string]$ClientLoader='zombieBuddy',
    [ValidateSet('Z','G1')][string]$GarbageCollector='Z',
    [string]$Pz3dLoaderJar=(Join-Path $PSScriptRoot '../pz3d/Contents.release/mods/pz3d/common/media/pz3d/loader/pz3dLoader.jar'),
    [switch]$StaggerClientLoading,
    [switch]$SkipBuild,
    [switch]$ValidateOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'game-session.ps1')
$modStudioSession=if(!$ValidateOnly){Start-ModStudioSession -Mode multiplayer -Source $Scenario -Checkout $PSScriptRoot}else{$null}
try {
$gcArgument=if($GarbageCollector -eq 'G1'){'-XX:+UseG1GC'}else{'-XX:+UseZGC'}
$suite=Get-Content -LiteralPath $Scenario -Raw | ConvertFrom-Json
if($suite.schema -ne 1 -or $suite.clients.Count -ne 2){throw 'Expected schema 1 and exactly two clients'}
if($suite.id -notmatch '^[a-z0-9_-]{1,60}$'){throw 'Invalid MP suite id'}
if($null -ne $suite.loadingTimeout){
    $loadingDeadline=$suite.loadingTimeout
    if($loadingDeadline -isnot [ValueType] -or ![double]::IsFinite([double]$loadingDeadline) -or $loadingDeadline -lt 1 -or $loadingDeadline -gt 3600){throw 'Invalid native loading timeout'}
}
if($null -ne $suite.prepareTimeout){
    $preparationDeadline=$suite.prepareTimeout
    if($preparationDeadline -isnot [ValueType] -or $preparationDeadline -is [bool] -or ![double]::IsFinite([double]$preparationDeadline) -or $preparationDeadline -lt 1 -or $preparationDeadline -gt 3600){throw 'Invalid provider preparation timeout'}
}
foreach($coordinate in @('x','y','z')){
    $value=$suite.spawn.$coordinate
    $min=if($coordinate -eq 'z'){-32}else{0};$max=if($coordinate -eq 'z'){31}else{100000}
    if($null -eq $value -or $value -isnot [ValueType] -or ![double]::IsFinite([double]$value) -or $value -ne [math]::Floor($value) -or $value -lt $min -or $value -gt $max){throw "Invalid MP spawn $coordinate"}
}
foreach($client in $suite.clients){
    if($client.loader -and $client.loader -notin @('zombieBuddy','pz3d')){throw 'Unsupported client loader'}
    if($client.steps.Count -lt 1 -or $client.steps.Count -gt 512){throw 'Expected 1..512 steps per client'}
    foreach($step in $client.steps){if($step.command -notmatch '^[a-z][a-z0-9_]*\.[a-z][a-zA-Z0-9_]*$'){throw 'Expected owner.command'}}
}
foreach($id in (@($suite.server.mods)+@($suite.clients | ForEach-Object {$_.mods}))){if($id -notmatch '^[A-Za-z0-9_-]+$'){throw 'Invalid native mod id'}}
foreach($property in $suite.server.options.psobject.Properties){if($property.Name -notmatch '^[A-Za-z0-9_.-]+$' -or [string]$property.Value -match '[\r\n]'){throw 'Invalid native server option'}}
foreach($property in $suite.server.javaProperties.psobject.Properties){if($property.Name -notmatch '^[A-Za-z0-9_.-]+$'){throw 'Invalid server Java property'}}
function Format-Sandbox($value,[int]$depth=0){
    if($depth -gt 8){throw 'Sandbox nesting limit'}
    if($value -is [bool]){return $value.ToString().ToLowerInvariant()}
    if($value -is [ValueType] -and [double]::IsFinite([double]$value)){return [string]::Format([Globalization.CultureInfo]::InvariantCulture,'{0}',$value)}
    if($value -is [pscustomobject]){
        $parts=@()
        foreach($property in $value.psobject.Properties){
            if($property.Name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$'){throw 'Invalid sandbox key'}
            $parts+="$($property.Name) = $(Format-Sandbox $property.Value ($depth+1)),"
        }
        return '{ '+($parts -join ' ')+' }'
    }
    throw 'MP sandbox values must be booleans, numbers or nested option tables'
}
$sandboxExtra=if($suite.server.sandbox){Format-Sandbox $suite.server.sandbox}else{'{ }'}
if($ValidateOnly){Write-Output 'MP suite preflight passed';return}
$live=Get-CimInstance Win32_Process | Where-Object {$_.Name -like 'ProjectZomboid*' -or ($_.Name -match '^javaw?\.exe$' -and $_.CommandLine -match 'zombie\.(gameStates\.MainScreenState|network\.GameServer)')}
if($live){throw "A game or server is already running: $($live.ProcessId -join ', ')"}
if(!$SkipBuild){& (Join-Path $PSScriptRoot 'build.ps1') -Game $Game}
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
$output=Join-Path $OutputRoot ([DateTime]::UtcNow.ToString('yyyyMMdd-THHmmssZ')+'-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
Copy-Item -LiteralPath $Scenario -Destination (Join-Path $output 'suite.json')
Write-Output "MP artifact: $output"
$acceptedTermsVersion=0
$nativeOptions=Join-Path $env:USERPROFILE 'Zomboid/options.ini'
if(Test-Path -LiteralPath $nativeOptions){
    $acceptedLine=Get-Content -LiteralPath $nativeOptions | Where-Object {$_ -match '^termsOfServiceVersion=[0-9]+$'} | Select-Object -First 1
    if($acceptedLine){$acceptedTermsVersion=[int]($acceptedLine.Split('=')[1])}
}
$selectedModSources=@{}
foreach($root in $ModRoots){
    $resolvedRoot=(Resolve-Path -LiteralPath $root).Path
    $packageRoot=Join-Path $resolvedRoot 'Contents/mods'
    if(!(Test-Path -LiteralPath $packageRoot -PathType Container)){throw 'Selected mod root has no native packages'}
    foreach($package in Get-ChildItem -LiteralPath $packageRoot -Directory){
        if($selectedModSources.ContainsKey($package.Name)){throw "Duplicate selected native mod: $($package.Name)"}
        $selectedModSources[$package.Name]=$package.FullName
    }
}
$sources=@{mod_studio=(Join-Path $PSScriptRoot 'Contents/mods/mod_studio')}
$workshop=Join-Path (Split-Path $Game) '../workshop/content/108600'
$buddy=Get-ChildItem -LiteralPath ([IO.Path]::GetFullPath($workshop)) -Directory | ForEach-Object {Join-Path $_.FullName 'mods/ZombieBuddy'} | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if(!$buddy){throw 'ZombieBuddy native mod not found'}
$sources.ZombieBuddy=$buddy
# Other mods use the same native package links; the runner has no renderer dependency.
foreach($id in (@($suite.server.mods)+@($suite.clients | ForEach-Object {$_.mods}) | Select-Object -Unique)){
    if($id -notmatch '^[A-Za-z0-9_-]+$'){throw "Invalid native mod id: $id"}
    if($sources.ContainsKey($id)){continue}
    if($selectedModSources.ContainsKey($id)){$sources[$id]=$selectedModSources[$id];continue}
    $source=Get-ChildItem -LiteralPath (Split-Path $PSScriptRoot) -Directory | ForEach-Object {Join-Path $_.FullName "Contents/mods/$id"} | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
    if(!$source){$source=Get-ChildItem -LiteralPath ([IO.Path]::GetFullPath($workshop)) -Directory | ForEach-Object {Join-Path $_.FullName "mods/$id"} | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1}
    if(!$source){throw "Native mod source not found: $id"}
    $sources[$id]=$source
}
if($ClientLoader -eq 'pz3d' -or @($suite.clients | Where-Object {$_.loader -eq 'pz3d'}).Count){$Pz3dLoaderJar=(Resolve-Path -LiteralPath $Pz3dLoaderJar).Path}
$runtime=@()
foreach($file in @('pz3dLoader.jar','pz3dLoader.dll','ZombieBuddy.jar')){
    $path=Join-Path $Game $file
    if(Test-Path -LiteralPath $path){$runtime+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}}
}
if(Test-Path -LiteralPath $Pz3dLoaderJar){$runtime+=@{role='selected-pz3d-loader';path=$Pz3dLoaderJar;sha256=(Get-FileHash -LiteralPath $Pz3dLoaderJar -Algorithm SHA256).Hash.ToLowerInvariant()}}
$runtime | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'runtime.json') -Encoding utf8
$config=Get-Content -LiteralPath (Join-Path $Game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
$port=$Port
$udp=$Port+1
# Fail before launching if these dedicated loopback ports belong to another process.
if(Get-NetUDPEndpoint -LocalPort $port,$udp -ErrorAction SilentlyContinue){throw 'MP test ports already occupied'}
function Prepare-Profile([string]$profile,[string[]]$mods){
    $root=Join-Path $output $profile
    New-Item -ItemType Directory -Path (Join-Path $root 'mods') -Force | Out-Null
    foreach($id in $sources.Keys){
        New-Item -ItemType Junction -Path (Join-Path $root "mods/$id") -Target $sources[$id] | Out-Null
    }
    $preset="VERSION = 1,`nmods`n{`n"+ (($mods | ForEach-Object {"    mod = $_,"}) -join "`n")+"`n}`nmaps`n{`n}`n"
    [IO.File]::WriteAllText((Join-Path $root 'mods/default.txt'),$preset)
    [IO.File]::WriteAllText((Join-Path $root 'mods/reset-mods-42_00.txt'),'Native 42.x profile initialized by Mod Studio.')
    [IO.File]::WriteAllText((Join-Path $root 'options.ini'),"version=8`nfullScreen=false`nborderless=false`nwidth=900`nheight=650`nfocusloss=false`nshowSurvivalGuide=false`nframeRate=30`nuncappedFPS=false`nvsync=false`nvoiceEnable=false`nmusicVolume=0`nlanguage=EN`ntermsOfServiceVersion=$acceptedTermsVersion`nlockCursorToWindow=false`n")
    # Native per-profile approval records are restricted to the exact test packages.
    # No global decisions, trust policy or signature checking are changed.
    $approvals=@()
    foreach($id in $sources.Keys){foreach($jar in Get-ChildItem -LiteralPath $sources[$id] -Recurse -Filter '*.jar'){
        $approvals+=@{id=$id;jar_hash=(Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256).Hash.ToLowerInvariant();decision=$true;time=[DateTime]::UtcNow.ToString('o')}
    }}
    $approvalDir=Join-Path $root 'ZombieBuddy'
    New-Item -ItemType Directory -Path $approvalDir -Force | Out-Null
    @{formatVersion=2;mods=$approvals} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $approvalDir 'mod_approvals.json') -Encoding utf8
    return $root
}
function Start-Native([string]$role,[string]$cache,[string[]]$Arguments){
    $start=[Diagnostics.ProcessStartInfo]::new();$start.FileName=Join-Path $Game 'jre64/bin/java.exe';$start.WorkingDirectory=$Game
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle='Hidden'
    $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true;$start.RedirectStandardInput=$true
    $start.ArgumentList.Add("-XX:ErrorFile=$cache/hs_err_pid%p.log")
    $start.ArgumentList.Add("-XX:ReplayDataFile=$cache/replay_pid%p.log")
    foreach($a in $Arguments){if($a -notmatch '^-XX:(ErrorFile|ReplayDataFile)='){$start.ArgumentList.Add($a)}}
    $process=[Diagnostics.Process]::Start($start)
    Update-ModStudioSession -Session $modStudioSession -Phase ("multiplayer: "+$role) -Artifact $output -Process $process -Role $role
    return @{role=$role;cache=$cache;process=$process;stdout=$process.StandardOutput.ReadToEndAsync();stderr=$process.StandardError.ReadToEndAsync()}
}
$owned=[Collections.Generic.List[object]]::new()
$launch=[ordered]@{garbageCollector=$GarbageCollector;clientLoader=$ClientLoader;schema=1;status='prepared';output=$output;serverMods=@($suite.server.mods);clients=@();processes=@();createdUtc=[DateTime]::UtcNow.ToString('o')}
try {
    $packages=@()
    foreach($mod in $sources.GetEnumerator()){
        if($mod.Key -notin (@($suite.server.mods)+@($suite.clients | ForEach-Object {$_.mods})+@('ZombieBuddy','mod_studio'))){continue}
        foreach($jar in Get-ChildItem -LiteralPath $mod.Value -Recurse -Filter '*.jar'){
            $packages+=@{id=$mod.Key;path=$jar.FullName;sha256=(Get-FileHash -LiteralPath $jar.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
        }
    }
    $packages | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'packages.json') -Encoding utf8
    # Declared native entrypoints, rather than every historical JAR in a mod folder,
    # identify the exact client build in the same diagnostics contract as SP.
    $clientProvenance=@{}
    $activePackages=@()
    foreach($mod in $sources.GetEnumerator()){
        $arguments=@();$declaredJar=$null
        $infos=@(Get-ChildItem -LiteralPath $mod.Value -Recurse -Filter mod.info)
        foreach($info in $infos){
            $fields=@{};foreach($line in Get-Content -LiteralPath $info.FullName){if($line -match '^([^=]+)=(.*)$'){$fields[$Matches[1]]=$Matches[2]}}
            if(!$fields.javaJarFile){continue}
            $jar=[IO.Path]::GetFullPath((Join-Path $info.DirectoryName $fields.javaJarFile))
            $hash=(Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash.ToLowerInvariant()
            $commit='unknown';$dirty=$null
            $gitRoot=git -C $mod.Value rev-parse --show-toplevel 2>$null
            if($LASTEXITCODE -eq 0){
                $commit=git -C $gitRoot rev-parse HEAD
                $dirty=@(git -C $gitRoot status --porcelain -- .).Count -gt 0
            }
            if($arguments.Count){
                if($declaredJar -eq $jar){continue}
                throw "Ambiguous native Java entrypoints for mod $($mod.Key): record the selected native version before launch"
            }
            $declaredJar=$jar
            $prefix="-Dmodstudio.scenario.$($fields.id)"
            $arguments=@("$prefix.commit=$commit","$prefix.dirty=$dirty","$prefix.jarSha256=$hash","$prefix.jarPath=$jar")
            $activePackages+=@{id=$fields.id;jar=$jar;sha256=$hash;commit=$commit;dirty=$dirty}
        }
        $clientProvenance[$mod.Key]=$arguments
    }
    $activePackages | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'active-packages.json') -Encoding utf8

    $luaSources=@()
    foreach($mod in $sources.GetEnumerator()){
        if($mod.Key -notin (@($suite.server.mods)+@($suite.clients | ForEach-Object {$_.mods})+@('ZombieBuddy','mod_studio'))){continue}
        $luaRoot=Join-Path $mod.Value 'common/media/lua'
        if(Test-Path -LiteralPath $luaRoot){foreach($file in Get-ChildItem -LiteralPath $luaRoot -Recurse -Filter '*.lua'){
            $luaSources+=@{id=$mod.Key;path=$file.FullName;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
        }}
    }
    $luaSources | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $output 'lua-sources.json') -Encoding utf8
    $serverCache=Prepare-Profile 'server'  @($suite.server.mods)
    New-Item -ItemType Directory -Path (Join-Path $serverCache 'Server') | Out-Null
    $ini=@('Public=false','Open=true','AutoCreateUserInWhiteList=true','PauseEmpty=false','PVP=false','UPnP=false','SteamVAC=false','DoLuaChecksum=true','WorkshopItems=','Map=Muldraugh, KY',"DefaultPort=$port","UDPPort=$udp",'MaxPlayers=2','PingLimit=0','BackupsOnStart=false','BackupsOnVersionChange=false','SaveWorldEveryMinutes=0',"Mods=$($suite.server.mods -join ';')", "SpawnPoint=$($suite.spawn.x),$($suite.spawn.y),$($suite.spawn.z)")
    if($suite.server.options){foreach($property in $suite.server.options.psobject.Properties){$value=if($property.Value -is [bool]){$property.Value.ToString().ToLowerInvariant()}else{[string]$property.Value};$ini+="$($property.Name)=$value"}}
    [IO.File]::WriteAllText((Join-Path $serverCache 'Server/ModStudioMP.ini'),($ini -join "`n")+"`n")
    [IO.File]::WriteAllText((Join-Path $serverCache 'Server/ModStudioMP_SandboxVars.lua'),"SandboxVars = { VERSION = 6, Zombies = 6, StartYear = 1, StartMonth = 7, StartDay = 9, StartTime = 2, WaterShutModifier = 365, ElecShutModifier = 365, StarterKit = false, $($sandboxExtra.Substring(1,$sandboxExtra.Length-2)) }")
    $vm=@($config.vmArgs | Where-Object {$_ -notmatch '^-Xmx|^-Dzomboid.steam|^-Djava.library.path|^-agentlib:pz3dLoader|^-agentpath:.*pz3dLoader\.dll|^-javaagent:.*(pz3dLoader|ZombieBuddy)|^-XX:[+-]Use(?:Z|G1|Parallel|Serial|Shenandoah)GC'})+@('-Xmx3072m',"-javaagent:$(Join-Path $Game 'ZombieBuddy.jar')=config_dir=$serverCache/ZombieBuddy",$gcArgument,'-Dzomboid.steam=0','-Djava.library.path=./natives/;./natives/win64/;./')
    if($suite.server.javaProperties){foreach($property in $suite.server.javaProperties.psobject.Properties){
        if($property.Name -notmatch '^[A-Za-z0-9_.-]+$'){throw 'Invalid server Java property'}
        $vm+="-D$($property.Name)=$($property.Value)"
    }}
    $server=Start-Native 'server' $serverCache ($vm+@('-cp','.;projectzomboid.jar','zombie.network.GameServer',"-cachedir=$serverCache",'-nosteam','-ip','127.0.0.1','-servername','ModStudioMP','-adminusername','TestA','-adminpassword','modstudio-test'))
    $owned.Add($server)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $serverConsole=Join-Path $serverCache 'server-console.txt'
    while($watch.Elapsed.TotalSeconds -lt 120){
        if($server.process.HasExited){throw 'Dedicated server exited during startup'}
        $serverText="";try {if(Test-Path -LiteralPath $serverConsole){$serverText=[string](Get-Content -LiteralPath $serverConsole -Raw -ErrorAction Stop)}} catch {}
        if($serverText -match '\*\*\* SERVER STARTED'){break}
        Start-Sleep -Milliseconds 500
    }
    if($watch.Elapsed.TotalSeconds -ge 120){throw 'Dedicated server startup timeout'}
    $server.process.StandardInput.WriteLine('adduser TestB modstudio-test')
    $server.process.StandardInput.WriteLine('setaccesslevel TestB admin')
    $server.process.StandardInput.Flush()
    Start-Sleep -Seconds 2
    # Observer first: the second launched window leaves the active driver focused.
    foreach($index in @(1,0)){
        $client=$suite.clients[$index];$loader=if($client.loader){$client.loader}else{$ClientLoader};$name=if($index -eq 0){'TestA'}else{'TestB'};$peer=if($index -eq 0){'TestB'}else{'TestA'}
        $mods=@('ZombieBuddy','mod_studio')+@($client.mods) | Select-Object -Unique
        $cache=Prepare-Profile "client-$name" $mods
        $definition=[ordered]@{schema=1;id=("$($suite.id)-$name").ToLowerInvariant();spawn=$suite.spawn;steps=$client.steps;multiplayer=@{host='127.0.0.1';port=$port;username=$name;password='modstudio-test';peer=$peer}}
        if($null -ne $suite.loadingTimeout){$definition.loadingTimeout=$suite.loadingTimeout}
        if($null -ne $suite.prepareTimeout){$definition.prepareTimeout=$suite.prepareTimeout}
        $scenarioPath=Join-Path $cache 'scenario.json';$definition | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $scenarioPath -Encoding utf8
        $clientVm=@($config.vmArgs | Where-Object {$_ -notmatch '^-Xmx|^-Dzomboid.steam|^-agentlib:pz3dLoader|^-agentpath:.*pz3dLoader\.dll|^-javaagent:.*(pz3dLoader|ZombieBuddy)|^-XX:[+-]Use(?:Z|G1|Parallel|Serial|Shenandoah)GC'})+@('-Xmx4096m',$gcArgument,'-Dzomboid.steam=0',"-javaagent:$(Join-Path $Game 'ZombieBuddy.jar')=config_dir=$cache/ZombieBuddy",'-Ddebug=true','-Dmodstudio.scenario.multiplayer=true',"-Dmodstudio.scenario=$scenarioPath","-Dmodstudio.scenario.output=$cache")
        foreach($id in $mods){$clientVm+=@($clientProvenance[$id])}
        if($loader -eq 'pz3d'){$clientVm+="-javaagent:$Pz3dLoaderJar"}
        $record=Start-Native $name $cache ($clientVm+@('-cp','.;projectzomboid.jar','zombie.gameStates.MainScreenState','-debug','-nosteam','-windowed',"-cachedir=$cache"))
        $owned.Add($record);$launch.clients+=@{loader=$loader;name=$name;mods=$mods;pid=$record.process.Id;cache=$cache}
        if($StaggerClientLoading -and $index -eq 1){
            $startupWatch=[Diagnostics.Stopwatch]::StartNew()
            $startupReady=$false
            $startupLimit=if($null -ne $suite.loadingTimeout){[double]$suite.loadingTimeout}else{240}
            while($startupWatch.Elapsed.TotalSeconds -lt $startupLimit){
                if($record.process.HasExited){throw "$name exited during staggered startup"}
                if($server.process.HasExited){throw 'Dedicated server exited during staggered startup'}
                $startupResult=Join-Path $cache 'scenario-result.json'
                if(Test-Path -LiteralPath $startupResult){$startupState=Get-Content -LiteralPath $startupResult -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue;if($startupState -and $startupState.status -notin @('running','complete')){throw "$name`: $($startupState.reason)"}}
                $startupProgress=Join-Path $cache 'progress.json'
                if(Test-Path -LiteralPath $startupProgress){$startupState=Get-Content -LiteralPath $startupProgress -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue;if($startupState -and $startupState.phase -ne 'loading'){$startupReady=$true;break}}
                Start-Sleep -Milliseconds 500
            }
            if(!$startupReady){throw "$name staggered startup timeout"}
            Write-Output "$name native loading finished; launching the second client."
        }
    }
    $launch.staggerClientLoading=[bool]$StaggerClientLoading
    $launch.status='launched';$launch.processes=@($owned | ForEach-Object {@{role=$_.role;pid=$_.process.Id}})
    $launch | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $output 'launch.json') -Encoding utf8
    $watch.Restart()
    while($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
        $done=$true
        foreach($entry in @($owned | Where-Object {$_.role -ne 'server'})){
            $resultPath=Join-Path $entry.cache 'scenario-result.json'
            if(Test-Path -LiteralPath $resultPath){
                $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if($result -and $result.status -notin @('running','complete')){throw "$($entry.role): $($result.reason)"}
            }else{$result=$null}
            if(!$result -or $result.status -ne 'complete'){$done=$false;if($entry.process.HasExited){throw "$($entry.role) exited without completion"}}
        }
        if($done){break}
        if($server.process.HasExited){throw 'Dedicated server exited during session'}
        Start-Sleep -Milliseconds 500
    }
    if(!$done){throw 'MP suite timeout'}
    $launch.status='complete'
} catch {
    $launch.status='failed';[IO.File]::WriteAllText((Join-Path $output 'abort.txt'),'Peer failure or suite timeout.');$launch.reason=$_.Exception.Message;$launch.errorPosition=$_.InvocationInfo.PositionMessage;Write-Warning ($launch.reason+' '+$launch.errorPosition)
} finally {
    foreach($entry in @($owned | Where-Object {$_.role -ne 'server'})){
        if(!$entry.process.HasExited){$entry.process.WaitForExit(15000) | Out-Null}
        if(!$entry.process.HasExited){$entry.process.Kill();$entry.process.WaitForExit();$launch.status='failed';$launch.reason=($launch.reason+'; client shutdown required termination').TrimStart('; ')}
    }
    if($server -and !$server.process.HasExited){$server.process.StandardInput.WriteLine('quit');$server.process.StandardInput.Flush();$server.process.WaitForExit(30000) | Out-Null}
    foreach($entry in $owned){
        if(!$entry.process.HasExited){$entry.process.Kill();$entry.process.WaitForExit();$launch.status='failed';$launch.reason=($launch.reason+'; server shutdown required termination').TrimStart('; ')}
        $launch.processes | Where-Object {$_.pid -eq $entry.process.Id} | ForEach-Object {$_['exitCode']=$entry.process.ExitCode}
        if($launch.status -eq 'complete' -and $entry.process.ExitCode -ne 0){$launch.status='failed';$launch.reason="$($entry.role) exited with $($entry.process.ExitCode)"}
        [IO.File]::WriteAllText((Join-Path $entry.cache 'stdout.txt'),$entry.stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $entry.cache 'stderr.txt'),$entry.stderr.GetAwaiter().GetResult())
        $entry.process.Dispose()
    }
    foreach($client in $launch.clients){
        if($client.mods -notcontains 'pz3d'){continue}
        $expectedOwner=if($client.loader -eq 'pz3d'){'Pz3dLoader'}else{'ZombieBuddy'}
        $consolePath=Join-Path $client.cache 'console.txt'
        $consoleText=if(Test-Path -LiteralPath $consolePath){[IO.File]::ReadAllText($consolePath)}else{''}
        $stdoutPath=Join-Path $client.cache 'stdout.txt'
        $stdoutText=if(Test-Path -LiteralPath $stdoutPath){[IO.File]::ReadAllText($stdoutPath)}else{''}
        if($launch.status -eq 'complete' -and !(Test-ModStudioLoaderOwner $consoleText $stdoutText $expectedOwner)){
            $launch.status='failed';$launch.reason="$($client.name): expected pz3d owner $expectedOwner was not confirmed"
        }
    }
    $changedSources=@()
    foreach($file in $luaSources){
        if(!(Test-Path -LiteralPath $file.path) -or (Get-FileHash -LiteralPath $file.path -Algorithm SHA256).Hash -ne $file.sha256){$changedSources+=$file.path}
    }
    if($changedSources.Count){$launch.changedSources=$changedSources;if($launch.status -eq 'complete'){$launch.status='failed';$launch.reason='Enabled Lua sources changed during session'}}
    $launch | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $output 'launch.json') -Encoding utf8
}
Write-Output "MP status: $($launch.status)"
if($launch.status -ne 'complete'){throw $launch.reason}
} finally {Stop-ModStudioSession $modStudioSession}
