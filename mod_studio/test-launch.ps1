[CmdletBinding()]
param([string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference = 'Stop'
$jdk = Join-Path $Game 'jre64\bin\java.exe'
$compiler = Join-Path $env:TEMP 'PZModBuild\ecj-3.44.0.jar'
if (!(Test-Path -LiteralPath $compiler)) { throw 'Run build.ps1 once to cache the Java compiler.' }
$classes = Join-Path $PSScriptRoot '.build\launch-test'
New-Item -ItemType Directory -Force -Path $classes | Out-Null
$classpath = Join-Path $Game 'projectzomboid.jar'
& $jdk -jar $compiler -25 -encoding UTF-8 -proc:none -nowarn -classpath $classpath -d $classes (Join-Path $PSScriptRoot 'tests\me\pavel\modstudio\LaunchRegression.java')
if ($LASTEXITCODE -ne 0) { throw 'Preset launch regression compilation failed.' }
Push-Location -LiteralPath $Game
try {
    & $jdk -cp "$classes;$classpath" me.pavel.modstudio.LaunchRegression $PSScriptRoot $Game
    if ($LASTEXITCODE -ne 0) { throw 'Preset launch regression failed.' }
} finally { Pop-Location }
