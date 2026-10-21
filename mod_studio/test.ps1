[CmdletBinding()]
param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$Compiler = '',
    [switch]$SkipBuild,
    [string]$LayoutPreview = '',
    [string]$JarPath = ''
)
$ErrorActionPreference = 'Stop'
if (!$SkipBuild) { & (Join-Path $PSScriptRoot 'build.ps1') -Game $Game -Compiler $Compiler }
if (!$Compiler) { $Compiler = Join-Path $env:TEMP 'PZModBuild\ecj-3.44.0.jar' }
$testRoot = Join-Path $PSScriptRoot ('.build\test-' + [guid]::NewGuid().ToString('N'))
$classes = Join-Path $testRoot 'classes'
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$java = Join-Path $Game 'jre64\bin\java.exe'
$buddy = Join-Path $Game 'ZombieBuddy.jar'
$jar = Join-Path $PSScriptRoot 'Contents\mods\mod_studio\42.20.4\media\java\client\ModStudio.jar'
if ($JarPath) { $jar = $JarPath }
$classpath = (Join-Path $Game 'projectzomboid.jar') + ';' + $buddy + ';' + $jar
$sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'tests') -Recurse -Filter '*.java' | ForEach-Object FullName)
& $java -jar $Compiler -25 -encoding UTF-8 -proc:none -nowarn -classpath $classpath -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }
Push-Location -LiteralPath $Game
try {
    $layoutArgs = @()
    if ($LayoutPreview) { $layoutArgs += "-Dmodstudio.layoutPreview=$LayoutPreview" }
    & $java @layoutArgs '--enable-native-access=ALL-UNNAMED' "-javaagent:${buddy}=config_dir=$testRoot\buddy" -cp "$classes;$classpath" me.pavel.modstudio.OfflineTest $Game (Join-Path $testRoot 'cache') $PSScriptRoot
    if ($LASTEXITCODE -ne 0) { throw 'Offline integration tests failed.' }
} finally { Pop-Location }
