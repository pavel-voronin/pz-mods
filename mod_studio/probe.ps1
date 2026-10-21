[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[1-9][0-9]{0,19}$')][string]$WorkshopId,
    [string]$Language = 'english',
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$Compiler = '',
    [switch]$Preview
)
$ErrorActionPreference = 'Stop'
if (!$Compiler) { $Compiler = Join-Path $env:TEMP 'PZModBuild\ecj-3.44.0.jar' }
if (!(Test-Path -LiteralPath $Compiler)) { throw 'Run build.ps1 first to prepare the compiler.' }
$classes = Join-Path $PSScriptRoot ('.build\probe-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$java = Join-Path $Game 'jre64\bin\java.exe'
$jar = Join-Path $PSScriptRoot 'Contents\mods\mod_studio\42.20.4\media\java\client\ModStudio.jar'
$classpath = $jar + ';' + (Join-Path $Game 'projectzomboid.jar') + ';' + (Join-Path $Game 'ZombieBuddy.jar')
& $java -jar $Compiler -25 -encoding UTF-8 -proc:none -nowarn -classpath $classpath -d $classes (Join-Path $PSScriptRoot 'tests\me\pavel\modstudio\ReadProbe.java')
if ($LASTEXITCODE -ne 0) { throw 'Probe compilation failed.' }
$previousAppId = $env:SteamAppId
$previousGameId = $env:SteamGameId
Push-Location -LiteralPath $Game
try {
    $env:SteamAppId = '108600'
    $env:SteamGameId = '108600'
    $previewArgs = @()
    if ($Preview) { $previewArgs += '--preview' }
    & $java '--enable-native-access=ALL-UNNAMED' '-Dstdout.encoding=UTF-8' '-Dstderr.encoding=UTF-8' -cp "$classes;$classpath" me.pavel.modstudio.ReadProbe (Join-Path $Game 'steam_api64.dll') $WorkshopId $Language @previewArgs
    if ($LASTEXITCODE -ne 0) { throw 'Steam read probe failed.' }
} finally {
    $env:SteamAppId = $previousAppId
    $env:SteamGameId = $previousGameId
    Pop-Location
}
