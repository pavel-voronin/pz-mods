[CmdletBinding()]
param([string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',[string]$JarPath='')
$ErrorActionPreference='Stop'
$classes=Join-Path $PSScriptRoot ('.build/input-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classes | Out-Null
$java=Join-Path $Game 'jre64/bin/java.exe'
$compiler=Join-Path $env:TEMP 'PZModBuild/ecj-3.44.0.jar'
$src=Join-Path $PSScriptRoot 'Contents/mods/mod_studio/42.20.4/java/src/me/pavel/modstudio'
$cp=(Join-Path $Game 'projectzomboid.jar')+';'+(Join-Path $Game 'ZombieBuddy.jar')
if(!$JarPath){$JarPath=Join-Path $PSScriptRoot 'Contents/mods/mod_studio/42.20.4/media/java/client/ModStudio.jar'}
$cp+=';'+$JarPath
$fixtures=@(Get-ChildItem (Join-Path $PSScriptRoot 'tests/fixtures/scenario-input') -Recurse -Filter '*.java' | ForEach-Object FullName)
& $java -jar $compiler -25 -encoding UTF-8 -proc:none -nowarn -cp $cp -d $classes (Join-Path $src 'ScenarioHost.java') (Join-Path $src 'ScenarioStatus.java') (Join-Path $src 'ScenarioPersistence.java') (Join-Path $src 'ScenarioJson.java') (Join-Path $src 'ScenarioInput.java') (Join-Path $PSScriptRoot 'tests/me/pavel/modstudio/ScenarioInputRegression.java') @fixtures
if($LASTEXITCODE -ne 0){throw 'Input regression compilation failed.'}
New-Item -ItemType Directory -Path (Join-Path $classes 'META-INF') | Out-Null
[IO.File]::WriteAllText((Join-Path $classes 'META-INF/MANIFEST.MF'),"Manifest-Version: 1.0`nPremain-Class: me.pavel.modstudio.ScenarioInputRegression`nCan-Retransform-Classes: true`nCan-Redefine-Classes: true`n`n")
Add-Type -AssemblyName System.IO.Compression.FileSystem
$jar=$classes+'.jar'
[IO.Compression.ZipFile]::CreateFromDirectory($classes,$jar)
Push-Location -LiteralPath $Game
try {
    & $java "-javaagent:$jar" -cp "$jar;$cp" me.pavel.modstudio.ScenarioInputRegression
    if($LASTEXITCODE -ne 0){throw 'Input regression failed.'}
} finally {Pop-Location}
