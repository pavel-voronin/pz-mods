[CmdletBinding()]
param([string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',[string]$PZ3D=(Join-Path $PSScriptRoot '../pz3d'))
$ErrorActionPreference='Stop'
$classes=Join-Path $PSScriptRoot ('.build/scenario-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classes | Out-Null
$java=Join-Path $Game 'jre64/bin/java.exe'
$compiler=Join-Path $env:TEMP 'PZModBuild/ecj-3.44.0.jar'
$src=Join-Path $PSScriptRoot 'Contents/mods/mod_studio/42.20.4/java/src/me/pavel/modstudio'
$cp=(Join-Path $Game 'projectzomboid.jar')+';'+(Join-Path $Game 'ZombieBuddy.jar')
& $java -jar $compiler -25 -encoding UTF-8 -proc:none -nowarn -cp $cp -d $classes (Join-Path $src 'ScenarioHost.java') (Join-Path $src 'ScenarioStatus.java') (Join-Path $src 'ScenarioPersistence.java') (Join-Path $src 'ScenarioJson.java') (Join-Path $src 'ScenarioDriving.java') (Join-Path $PSScriptRoot 'tests/me/pavel/modstudio/ScenarioRegression.java') (Join-Path $PSScriptRoot 'tests/me/pavel/modstudio/ScenarioStatusRegression.java')
if($LASTEXITCODE -ne 0){throw 'Scenario regression compilation failed.'}
Push-Location -LiteralPath $Game
try {
    & $java -cp "$classes;$cp" me.pavel.modstudio.ScenarioRegression $PSScriptRoot $PZ3D
    if($LASTEXITCODE -ne 0){throw 'Scenario regression failed.'}
    & $java -cp "$classes;$cp" me.pavel.modstudio.ScenarioStatusRegression
    if($LASTEXITCODE -ne 0){throw 'Scenario status regression failed.'}
} finally {Pop-Location}
