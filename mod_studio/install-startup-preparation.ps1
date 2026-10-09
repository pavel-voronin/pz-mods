[CmdletBinding()]
param([Parameter(Mandatory)][string]$StageJson,
    [string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'game-session.ps1')
$lease=Start-ModStudioSession -Mode startup-install -Source $StageJson -Checkout $PSScriptRoot
try {
    $running=@(Get-CimInstance Win32_Process | Where-Object {
        $_.Name -like 'ProjectZomboid*' -or ($_.Name -match '^javaw?\.exe$' -and $_.CommandLine -match 'zombie\.(gameStates\.MainScreenState|network\.GameServer)')
    } | Where-Object {try{!(Get-Process -Id $_.ProcessId -ErrorAction Stop).HasExited}catch{$false}})
    if($running){throw 'A game or server is running; installation requires it to exit normally'}
    & (Join-Path $PSScriptRoot 'test-stage-preparation.ps1') -StageJson $StageJson -Game $Game
    $stage=Get-Content -LiteralPath $StageJson -Raw | ConvertFrom-Json
    if(!$stage.defaultEnabled){throw 'Production installation requires verified defaults'}
    $target=[string]$stage.baseJar
    $backup=Join-Path (Split-Path $stage.jar) 'installed-before'
    New-Item -ItemType Directory -Path $backup | Out-Null
    Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'ModStudio.jar')
    Copy-Item -LiteralPath ($target+'.zbs') -Destination (Join-Path $backup 'ModStudio.jar.zbs')
    $next=$target+'.startup-next'
    $nextSignature=$target+'.zbs.startup-next'
    Copy-Item -LiteralPath $stage.jar -Destination $next
    Copy-Item -LiteralPath ($stage.jar+'.zbs') -Destination $nextSignature
    if((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -ne $stage.baseSha256){throw 'Installed JAR changed; refusing replacement'}
    try {
        [IO.File]::Move($next,$target,$true)
        [IO.File]::Move($nextSignature,$target+'.zbs',$true)
        if((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -ne $stage.jarSha256){throw 'Installed JAR verification failed'}
        if((Get-FileHash -LiteralPath ($target+'.zbs')).Hash -ne (Get-FileHash -LiteralPath ($stage.jar+'.zbs')).Hash){throw 'Installed signature verification failed'}
    } catch {
        [IO.File]::WriteAllBytes($target,[IO.File]::ReadAllBytes((Join-Path $backup 'ModStudio.jar')))
        [IO.File]::WriteAllBytes($target+'.zbs',[IO.File]::ReadAllBytes((Join-Path $backup 'ModStudio.jar.zbs')))
        throw
    }
    $stage.installed=$true
    $stage | Add-Member -NotePropertyName installedUtc -NotePropertyValue ([DateTime]::UtcNow.ToString('o'))
    $stage | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StageJson -Encoding utf8
    Write-Output "Installed default startup preparation: $target | SHA256=$($stage.jarSha256)"
} finally {Stop-ModStudioSession $lease}
