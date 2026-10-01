[CmdletBinding()]
param(
    [string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [ValidateRange(1,600)][int]$Seconds=5,
    [ValidateRange(1,1200)][int]$TimeoutSeconds=180,
    [ValidateSet('Configured','None','Buddy','Pz3dLoaderJava','Pz3dLoaderNative')][string]$Loaders='Configured',
    [ValidateSet('Java','Native')][string]$Launcher='Java',
    [switch]$WithBuddy,
    [switch]$ReloadLua,
    [string]$EnableModOnReload='',
    [string[]]$Mods
)
$ErrorActionPreference='Stop'
if($EnableModOnReload){
    if($EnableModOnReload -notmatch '^[a-zA-Z0-9_-]+$'){throw 'Invalid mod id for Lua reload.'}
    $ReloadLua=$true
}
if($Launcher -eq 'Native' -and $Loaders -ne 'Configured'){throw 'Native launcher uses its installed configuration; use Java to isolate loaders.'}
. (Join-Path $PSScriptRoot 'process.ps1')
$running=if($IsLinux){
    Get-Process | Where-Object {
        if($_.ProcessName -like 'ProjectZomboid*'){return $true}
        if($_.ProcessName -notmatch '^java$'){return $false}
        $cmdline=Get-Content -LiteralPath "/proc/$($_.Id)/cmdline" -Raw -ErrorAction SilentlyContinue
        $cmdline -match 'zombie[./]gameStates[./]MainScreenState'
    }
}else{Get-CimInstance Win32_Process | Where-Object {
    $_.Name -like 'ProjectZomboid*' -or ($_.Name -match '^javaw?\.exe$' -and $_.CommandLine -match 'zombie.gameStates.MainScreenState')
}}
if(!$IsLinux){$running=@($running | Where-Object {try{!(Get-Process -Id $_.ProcessId -ErrorAction Stop).HasExited}catch{$false}})}
if($running){throw 'Project Zomboid is already running; an existing session will not be closed.'}
$cache=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid'
if($IsLinux -and $Loaders -eq 'Pz3dLoaderNative'){throw 'Pz3dLoaderNative is only supported on Windows.'}
if($IsLinux -and $Launcher -eq 'Native'){throw 'Linux menu checks currently use the Java launcher.'}
$token=[guid]::NewGuid().ToString('N')
$output=Join-Path $cache ('ModStudio/scenarios/'+[DateTime]::UtcNow.ToString('yyyyMMdd-THHmmssZ')+'-'+$token)
New-Item -ItemType Directory -Path $output | Out-Null
$luaCache=Join-Path $cache 'Lua/ModStudio'
New-Item -ItemType Directory -Path $luaCache -Force | Out-Null
$request=Join-Path $luaCache 'menu-request.txt'
if(Test-Path -LiteralPath $request){throw "Another menu request exists: $request"}
$active=Join-Path $cache 'mods/default.txt'
New-Item -ItemType Directory -Path (Split-Path $active) -Force | Out-Null
$hadActive=Test-Path -LiteralPath $active
$saved=if($hadActive){[IO.File]::ReadAllBytes($active)}else{$null}
$result=Join-Path $luaCache "menu-$token.json"
$reloadMarker=Join-Path $luaCache "menu-$token-reloaded.txt"
$launch=[ordered]@{schema=1;mode='menu';status='prepared';output=$output;createdUtc=[DateTime]::UtcNow.ToString('o');loaders=$Loaders;launcher=$Launcher;seconds=$Seconds;reloadLua=[bool]$ReloadLua;enableModOnReload=$EnableModOnReload}
try {
    if($hadActive){[IO.File]::WriteAllBytes((Join-Path $output 'active-mods-before.txt'),$saved)}
    if($PSBoundParameters.ContainsKey('Mods')){
        foreach($mod in $Mods){if($mod -notmatch '^[a-zA-Z0-9_-]+$'){throw "Invalid mod id: $mod"}}
        $text="VERSION = 1,`nmods`n{`n"+((@($Mods)+@('mod_studio_menu') | Select-Object -Unique | ForEach-Object {"    mod = $_,"}) -join "`n")+"`n}`nmaps`n{`n}`n"
    }else{
        $text=if($hadActive){[Text.Encoding]::UTF8.GetString($saved)}else{"VERSION = 1,`nmods`n{`n}`nmaps`n{`n}"}
        if($text -notmatch 'mod\s*=\s*mod_studio_menu\s*,'){
            if($text -notmatch 'mods\s*\{'){throw 'Cannot find native default mod list'}
            $text=[regex]::Replace($text,'mods\s*\{',"mods`n{`n    mod = mod_studio_menu,",1)
        }
    }
    [IO.File]::WriteAllText($active,$text,[Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $active -Destination (Join-Path $output 'active-mods.txt')
    [IO.File]::WriteAllText($request,"$token`n$Seconds`n$([int][bool]$ReloadLua)`n$EnableModOnReload`n",[Text.UTF8Encoding]::new($false))
    $config=Get-Content -LiteralPath (Join-Path $Game 'ProjectZomboid64.json') -Raw | ConvertFrom-Json
    $arguments=@($config.vmArgs)
    if($Loaders -ne 'Configured'){$arguments=@($arguments | Where-Object {$_ -notmatch '^-((javaagent|agentlib|agentpath):)'})}
    if($Loaders -eq 'Buddy'){$arguments+="-javaagent:$(Join-Path $Game 'ZombieBuddy.jar')"}
    if($Loaders -eq 'Pz3dLoaderJava'){$arguments+="-javaagent:$(Join-Path $Game 'pz3dLoader.jar')"}
    if($Loaders -eq 'Pz3dLoaderNative'){$arguments+="-agentpath:$(Join-Path $Game 'pz3dLoader.dll')"}
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=Join-Path $Game $(if($IsLinux){'jre64/bin/java'}else{'jre64/bin/java.exe'});$start.WorkingDirectory=$Game
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    if($IsLinux){
        $start.Environment['LD_LIBRARY_PATH']="$Game/natives:${Game}:$Game/jre64/lib:"+$env:LD_LIBRARY_PATH
        $start.Environment['LD_PRELOAD']="$Game/jre64/lib/libjsig.so:$Game/natives/libPZXInitThreads64.so"
        $start.Environment['XMODIFIERS']=''
    }
    if($Launcher -eq 'Native'){
        $start.FileName=Join-Path $Game 'ProjectZomboid64.exe'
        if($WithBuddy){$start.ArgumentList.Add('-agentlib:zbNative=policy=allow-all')}
        $start.ArgumentList.Add('--')
    }else{
        if($WithBuddy -and $Loaders -ne 'Buddy'){$arguments+="-javaagent:$(Join-Path $Game 'ZombieBuddy.jar')"}
        foreach($arg in ($arguments+@('-cp',($config.classpath -join [IO.Path]::PathSeparator),'zombie.gameStates.MainScreenState'))){$start.ArgumentList.Add($arg)}
    }
    Write-Output "Menu artifact: $output"
    Invoke-ModStudioProcess -Start $start -Launch $launch -Output $output -TimeoutSeconds $TimeoutSeconds -ResultPath $result
    $screenshot=Join-Path $cache "Screenshots/modstudio-menu-$token.png"
    if(Test-Path -LiteralPath $screenshot){Move-Item -LiteralPath $screenshot -Destination (Join-Path $output 'menu.png')}
    if(!(Test-Path -LiteralPath (Join-Path $output 'menu.png'))){
        $launch.status='failed';$launch.reason='Menu screenshot was not saved'
        $launch | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'launch.json') -Encoding utf8
        @{schema=1;status='failed';reason=$launch.reason;token=$token} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'scenario-result.json') -Encoding utf8
        throw $launch.reason
    }
} finally {
    # Restore the exact bytes, including when startup or result parsing fails.
    if($hadActive){[IO.File]::WriteAllBytes($active,$saved)}elseif(Test-Path -LiteralPath $active){Remove-Item -LiteralPath $active}
    if(Test-Path -LiteralPath $request){Remove-Item -LiteralPath $request}
    if(Test-Path -LiteralPath $result){Remove-Item -LiteralPath $result}
    if(Test-Path -LiteralPath $reloadMarker){Remove-Item -LiteralPath $reloadMarker}
}
