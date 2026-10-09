[CmdletBinding()]
param([string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid',
    [string]$BaseJar='C:\Users\pavel\Zomboid\Workshop\mod_studio\Contents\mods\mod_studio\42.20.4\media\java\client\ModStudio.jar')
$ErrorActionPreference='Stop'
$compiler=Join-Path $env:TEMP 'PZModBuild/ecj-3.44.0.jar'
if(!(Test-Path $compiler) -or (Get-FileHash $compiler -Algorithm SHA256).Hash -ne '14C46DDC2E511C46C998DA728F6A80F13A689C920F3832402F7AD150F6A6188D'){throw 'Missing verified compiler'}
$baseBytes=[IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $BaseJar).Path)
$baseHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($baseBytes)).ToLowerInvariant()
$directory=Join-Path $PSScriptRoot ('.build/game-preparation-'+[guid]::NewGuid().ToString('N'))
$classes=Join-Path $directory 'classes'
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$names=@('StartupPreparationPolicy','LuaPreparation','LuaPreparationHooks','LuaFolderScan','ScriptBlockParser','ItemParameterDispatch','StartupLuaDiagnostics','AnimationFrameCollector','AnimationKeyLookup','ClipFrameIndex','TranslationPreparation','SaveDirectoryPreparation')
$sources=@($names | ForEach-Object {Join-Path $PSScriptRoot "Contents/mods/mod_studio/42.20.4/java/src/me/pavel/modstudio/$_.java"})
$java=Join-Path $Game 'jre64/bin/java.exe'
$gameJar=Join-Path $Game 'projectzomboid.jar'
$buddyJar=Join-Path $Game 'ZombieBuddy.jar'
& $java -jar $compiler -25 -encoding UTF-8 -proc:none -nowarn -classpath "$gameJar;$buddyJar" -d $classes @sources
if($LASTEXITCODE -ne 0){throw 'Startup preparation compilation failed'}
$jar=Join-Path $directory 'ModStudio.game-preparation.jar'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$inputStream=[IO.MemoryStream]::new($baseBytes,$false)
$inputArchive=[IO.Compression.ZipArchive]::new($inputStream,[IO.Compression.ZipArchiveMode]::Read)
$outputStream=[IO.File]::Create($jar)
$outputArchive=[IO.Compression.ZipArchive]::new($outputStream,[IO.Compression.ZipArchiveMode]::Create)
try {
    foreach($entry in $inputArchive.Entries){
        $replace=$false
        foreach($name in $names){if($entry.FullName -eq "me/pavel/modstudio/$name.class" -or $entry.FullName.StartsWith('me/pavel/modstudio/'+$name+'$')){$replace=$true;break}}
        if($replace){continue}
        $copy=$outputArchive.CreateEntry($entry.FullName,[IO.Compression.CompressionLevel]::Optimal)
        $copy.LastWriteTime=$entry.LastWriteTime
        $source=$entry.Open();$destination=$copy.Open()
        try{$source.CopyTo($destination)}finally{$destination.Dispose();$source.Dispose()}
    }
    foreach($file in @(Get-ChildItem -LiteralPath $classes -Recurse -File | Sort-Object FullName)){
        $relative=$file.FullName.Substring($classes.Length+1).Replace('\','/')
        $entry=$outputArchive.CreateEntry($relative,[IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime=[DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
        $source=$file.OpenRead();$destination=$entry.Open()
        try{$source.CopyTo($destination)}finally{$destination.Dispose();$source.Dispose()}
    }
} finally {$outputArchive.Dispose();$outputStream.Dispose();$inputArchive.Dispose();$inputStream.Dispose()}
& (Join-Path $PSScriptRoot 'sign.ps1') -JarPath $jar -Game $Game -Compiler $compiler
if($LASTEXITCODE -ne 0){throw 'Startup preparation signing failed'}
$metadata=[ordered]@{schema=1;createdUtc=[DateTime]::UtcNow.ToString('o');baseJar=$BaseJar;baseSha256=$baseHash;jar=$jar;jarSha256=(Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash.ToLowerInvariant();gameSha256=(Get-FileHash -LiteralPath $gameJar -Algorithm SHA256).Hash.ToLowerInvariant();buddySha256=(Get-FileHash -LiteralPath $buddyJar -Algorithm SHA256).Hash.ToLowerInvariant();features=@('Lua','Definitions','ItemDispatch','Animations','Diagnostics','MenuData');defaultFeatures=@('Lua','Definitions','ItemDispatch','Animations');defaultEnabled=$true;installed=$false}
[IO.File]::WriteAllText((Join-Path $directory 'stage.json'),($metadata | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output "Staged ordinary Mod Studio patches: $jar"
