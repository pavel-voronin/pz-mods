[CmdletBinding()]
param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$ZombieBuddy = '',
    [string]$Compiler = '',
    [switch]$Staged
)
$ErrorActionPreference = 'Stop'
if (!$ZombieBuddy) { $ZombieBuddy = Join-Path $Game 'ZombieBuddy.jar' }
if (!$Compiler) {
    $compilerCache = Join-Path $env:TEMP 'PZModBuild'
    New-Item -ItemType Directory -Path $compilerCache -Force | Out-Null
    $Compiler = Join-Path $compilerCache 'ecj-3.44.0.jar'
    if (!(Test-Path -LiteralPath $Compiler)) {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://repo.maven.apache.org/maven2/org/eclipse/jdt/ecj/3.44.0/ecj-3.44.0.jar' -OutFile $Compiler
    }
}
if ((Get-FileHash -LiteralPath $Compiler -Algorithm SHA256).Hash -ne '14C46DDC2E511C46C998DA728F6A80F13A689C920F3832402F7AD150F6A6188D') { throw 'Unexpected compiler checksum.' }
$modRoot = Join-Path $PSScriptRoot 'Contents\mods\mod_studio\42.20.4'
$buildRoot = Join-Path $PSScriptRoot '.build'
$classes = Join-Path $buildRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$java = Join-Path $Game 'jre64\bin\java.exe'
$manifestClient = & (Join-Path $PSScriptRoot 'manifest-build.ps1') -Game $Game -Compiler $Compiler
$libraryDir = Join-Path $classes 'me\pavel\modstudio\lib'
New-Item -ItemType Directory -Path $libraryDir -Force | Out-Null
Copy-Item -LiteralPath $manifestClient -Destination (Join-Path $libraryDir 'manifest-client.jar')
$classpath = (Join-Path $Game 'projectzomboid.jar') + ';' + $ZombieBuddy
$sources = @(Get-ChildItem -LiteralPath (Join-Path $modRoot 'java\src') -Recurse -Filter '*.java' | ForEach-Object FullName)
& $java -jar $Compiler -25 -encoding UTF-8 -proc:none -nowarn -classpath $classpath -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw 'Java compilation failed.' }
$jarDir = Join-Path $modRoot 'media\java\client'
New-Item -ItemType Directory -Path $jarDir -Force | Out-Null
$jarPath = Join-Path $jarDir 'ModStudio.jar'
if ($Staged) { $jarPath = Join-Path $buildRoot 'ModStudio.next.jar' }
$stagedJar = Join-Path $buildRoot (([guid]::NewGuid().ToString('N')) + '.jar')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$jarStream = [IO.File]::Create($stagedJar)
$archive = [IO.Compression.ZipArchive]::new($jarStream, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $classes -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relative = $_.FullName.Substring($classes.Length + 1).Replace('\','/')
        $entry = $archive.CreateEntry($relative, [IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = [DateTimeOffset]::new(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
        $outStream = $entry.Open()
        $inStream = $_.OpenRead()
        try { $inStream.CopyTo($outStream) } finally { $inStream.Dispose(); $outStream.Dispose() }
    }
} finally { $archive.Dispose(); $jarStream.Dispose() }
& (Join-Path $PSScriptRoot 'sign.ps1') -JarPath $stagedJar -Game $Game -Compiler $Compiler
# Replace only a complete archive; a running game can keep the previous JAR locked.
if (!(Test-Path -LiteralPath $jarPath) -or
    (Get-FileHash -LiteralPath $stagedJar -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $jarPath -Algorithm SHA256).Hash) {
    [IO.File]::Move($stagedJar, $jarPath, $true)
}
[IO.File]::Move($stagedJar + '.zbs', $jarPath + '.zbs', $true)
Write-Output "Built $jarPath"
