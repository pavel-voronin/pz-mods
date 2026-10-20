[CmdletBinding()]
param([string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$classes=Join-Path $PSScriptRoot ('.build/barricade-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classes | Out-Null
$java=Join-Path $Game 'jre64/bin/java.exe'
$compiler=Join-Path $env:TEMP 'PZModBuild/ecj-3.44.0.jar'
$classpath=Join-Path $Game 'projectzomboid.jar'
& $java -jar $compiler -25 -encoding UTF-8 -proc:none -nowarn -cp $classpath -d $classes (Join-Path $PSScriptRoot 'tests/me/pavel/modstudio/BarricadeScenarioRegression.java')
if($LASTEXITCODE -ne 0){throw 'Barricade scenario test compilation failed'}
Push-Location -LiteralPath $Game
try {
    & $java -cp "$classes;$classpath" me.pavel.modstudio.BarricadeScenarioRegression $PSScriptRoot
    if($LASTEXITCODE -ne 0){throw 'Barricade scenario regression failed'}
} finally {Pop-Location}
