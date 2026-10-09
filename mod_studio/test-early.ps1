param([string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$jar=& (Join-Path $PSScriptRoot 'build-early.ps1') -Game $Game
$classes=Join-Path $PSScriptRoot ('.build/early-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$compiler=Join-Path $env:TEMP 'PZModBuild/ecj-3.44.0.jar'
$java=Join-Path $Game 'jre64/bin/java.exe'
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'startup/tests/zombie') -Filter '*.java' -Recurse | ForEach-Object FullName)
$sources+=Join-Path $PSScriptRoot 'startup/tests/me/pavel/modstudio/startup/ModStudioEarlyAgentTest.java'
$sources+=Join-Path $PSScriptRoot 'startup/tests/me/pavel/modstudio/startup/ModStudioEarlyDisabledTest.java'
$sources+=Join-Path $PSScriptRoot 'startup/tests/me/pavel/modstudio/preloadfixture/StartupPreloadFixture.java'
& $java -jar $compiler -25 -proc:none -nowarn -encoding UTF-8 -classpath "$jar;$Game/projectzomboid.jar" -d $classes @sources
if($LASTEXITCODE -ne 0){throw 'Production early fixture compilation failed'}
$preloadJar=Join-Path $classes 'preload.jar'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$preloadArchive=[IO.Compression.ZipFile]::Open($preloadJar,[IO.Compression.ZipArchiveMode]::Create)
try{
    $writer=[IO.StreamWriter]::new($preloadArchive.CreateEntry('META-INF/MANIFEST.MF').Open(),[Text.UTF8Encoding]::new($false))
    try{$writer.Write("Manifest-Version: 1.0`r`nPremain-Class: me.pavel.modstudio.preloadfixture.StartupPreloadFixture`r`n`r`n")}finally{$writer.Dispose()}
    [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($preloadArchive,(Join-Path $classes 'me/pavel/modstudio/preloadfixture/StartupPreloadFixture.class'),'me/pavel/modstudio/preloadfixture/StartupPreloadFixture.class')
}finally{$preloadArchive.Dispose()}
$archive=[IO.Compression.ZipFile]::OpenRead($jar)
try{if(@($archive.Entries | Where-Object {$_.FullName -match 'StartupPatchBatch|/StartupAgent(\$|\.class)'}).Count){throw 'Production archive contains experimental loader code'}}finally{$archive.Dispose()}
Push-Location -LiteralPath $Game
try {
    & $java "-javaagent:$jar" -cp "$classes;$jar;$Game/projectzomboid.jar" me.pavel.modstudio.startup.ModStudioEarlyAgentTest
    if($LASTEXITCODE -ne 0){throw 'Production early agent regression failed'}
    & $java "-javaagent:$preloadJar" "-javaagent:$jar" -cp "$classes;$jar;$Game/ZombieBuddy.jar;$Game/projectzomboid.jar" me.pavel.modstudio.startup.ModStudioEarlyAgentTest
    if($LASTEXITCODE -ne 0){throw 'Preloaded production early agent regression failed'}
    & $java "-javaagent:$jar" '-Dmodstudio.startup.early=false' -cp "$classes;$jar;$Game/projectzomboid.jar" me.pavel.modstudio.startup.ModStudioEarlyDisabledTest
    if($LASTEXITCODE -ne 0){throw 'Explicit early disable regression failed'}
}finally{Pop-Location}
# Unsupported working directory/build must leave the JVM usable, not abort launch.
Push-Location -LiteralPath $classes
try{
    & $java "-javaagent:$jar" -cp "$classes;$jar;$Game/projectzomboid.jar" me.pavel.modstudio.startup.ModStudioEarlyDisabledTest
    if($LASTEXITCODE -ne 0){throw 'Unavailable game early fallback failed'}
}finally{Pop-Location}
Write-Output "Production early artifact: $jar"
