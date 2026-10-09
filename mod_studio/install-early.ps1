[CmdletBinding()]
param([string]$AgentJar=(Join-Path $PSScriptRoot '.build/ModStudioEarly.jar'),
    [string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'game-session.ps1')
$lease=Start-ModStudioSession -Mode early-install -Source $AgentJar -Checkout $PSScriptRoot
try {
    $running=@(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -like 'ProjectZomboid*' -or ($_.Name -match '^javaw?\.exe$' -and $_.CommandLine -match 'zombie\.(gameStates\.MainScreenState|network\.GameServer)')
    } | Where-Object {try{!(Get-Process -Id $_.ProcessId -ErrorAction Stop).HasExited}catch{$false}})
    if($running){throw 'An existing game or server must exit normally before installation'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $AgentJar).Path)
    try {
        if(@($archive.Entries | Where-Object {$_.FullName -match 'StartupPatchBatch|/StartupAgent(\$|\.class)'}).Count){throw 'Refusing experimental loader code'}
        $reader=[IO.StreamReader]::new($archive.GetEntry('META-INF/MANIFEST.MF').Open())
        try{$manifest=$reader.ReadToEnd().Replace("`r`n ",'')}finally{$reader.Dispose()}
        if($manifest -notmatch 'Premain-Class: me\.pavel\.modstudio\.startup\.ModStudioEarlyAgent\r?\n'){throw 'Unexpected agent entry point'}
        $hash=(Get-FileHash -LiteralPath (Join-Path $Game 'projectzomboid.jar')).Hash.ToLowerInvariant()
        if($manifest -notmatch "Implementation-Version: $hash\r?\n"){throw 'Agent was built for another game version'}
    }finally{$archive.Dispose()}
    $configPath=Join-Path $Game 'ProjectZomboid64.json'
    $original=[IO.File]::ReadAllBytes($configPath)
    $config=[Text.Encoding]::UTF8.GetString($original) | ConvertFrom-Json
    $destination=Join-Path $Game 'ModStudioEarly.jar'
    $argument="-javaagent:$destination"
    $config.vmArgs=@($argument)+@($config.vmArgs | Where-Object {$_ -notmatch '^-javaagent:.*[\\/]ModStudioEarly\.jar(?:=.*)?$'})
    $backup=Join-Path $PSScriptRoot ('.build/early-installed-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $backup 'ProjectZomboid64.before.json'),$original)
    $hadJar=Test-Path -LiteralPath $destination
    if($hadJar){Copy-Item -LiteralPath $destination -Destination (Join-Path $backup 'ModStudioEarly.before.jar')}
    Copy-Item -LiteralPath $AgentJar -Destination ($destination+'.next')
    [IO.File]::WriteAllText($configPath+'.next',($config | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($configPath))) -ne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($original))){throw 'Launcher configuration changed; refusing replacement'}
    try {
        [IO.File]::Move($destination+'.next',$destination,$true)
        [IO.File]::Move($configPath+'.next',$configPath,$true)
        if((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $AgentJar).Hash){throw 'Installed agent fingerprint differs'}
        $installed=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if($installed.vmArgs[0] -ne $argument){throw 'Early agent is not the first JVM argument'}
    }catch {
        [IO.File]::WriteAllBytes($configPath,$original)
        if($hadJar){Copy-Item -LiteralPath (Join-Path $backup 'ModStudioEarly.before.jar') -Destination $destination -Force}
        else{Remove-Item -LiteralPath $destination -ErrorAction SilentlyContinue}
        throw
    }
    [ordered]@{installedUtc=[DateTime]::UtcNow.ToString('o');agent=$destination;sha256=(Get-FileHash -LiteralPath $destination).Hash.ToLowerInvariant();gameSha256=$hash;config=$configPath;backup=$backup;gameLaunched=$false;thirdPartyLoadersChanged=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'installation.json') -Encoding utf8
    Write-Output "Installed Mod Studio early agent for ordinary launches: $destination"
    Write-Output "Original launcher configuration preserved: $backup"
}finally{Stop-ModStudioSession $lease}
