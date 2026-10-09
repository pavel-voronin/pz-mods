[CmdletBinding()]
param([string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$Production=$true
$ErrorActionPreference='Stop'
$compiler=Join-Path $env:TEMP 'PZModBuild/ecj-3.44.0.jar'
if(!(Test-Path -LiteralPath $compiler)){
    New-Item -ItemType Directory -Path (Split-Path $compiler) -Force | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri 'https://repo.maven.apache.org/maven2/org/eclipse/jdt/ecj/3.44.0/ecj-3.44.0.jar' -OutFile $compiler
}
if((Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash -ne '14C46DDC2E511C46C998DA728F6A80F13A689C920F3832402F7AD150F6A6188D'){throw 'Unexpected compiler checksum'}
$build=Join-Path $PSScriptRoot ('.build/startup-'+[guid]::NewGuid().ToString('N'))
$classes=Join-Path $build 'classes'
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$java=Join-Path $Game 'jre64/bin/java.exe'
$buddy=Join-Path $Game 'ZombieBuddy.jar'
$sources=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'startup/java') -Filter '*.java' -Recurse | ForEach-Object FullName)
if($Production){$sources=@($sources | Where-Object {[IO.Path]::GetFileNameWithoutExtension($_) -in @('ModStudioEarlyAgent','EarlyGameAdvice','StartupScanner','StartupWatch','StartupScripts','StartupTrace')})}
& $java -jar $compiler -25 -encoding UTF-8 -proc:none -nowarn -classpath "$(Join-Path $Game 'projectzomboid.jar');$buddy" -d $classes @sources
if($LASTEXITCODE -ne 0){throw 'Startup agent compilation failed'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$jar=Join-Path $PSScriptRoot '.build/ModStudioStartup.jar'
if($Production){$jar=Join-Path $PSScriptRoot '.build/ModStudioEarly.jar'}
$staged=Join-Path $build 'ModStudioStartup.jar'
$stream=[IO.File]::Create($staged)
$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
$dependency=[IO.Compression.ZipFile]::OpenRead($buddy)
try{
    $manifest=$archive.CreateEntry('META-INF/MANIFEST.MF')
    $writer=[IO.StreamWriter]::new($manifest.Open(),[Text.UTF8Encoding]::new($false))
    $hash=(Get-FileHash -LiteralPath (Join-Path $Game 'projectzomboid.jar') -Algorithm SHA256).Hash.ToLowerInvariant()
    # Manifest physical lines must be at most 72 bytes.
    $version="Implementation-Version: $hash"
    $vendor="Implementation-Vendor: $((Get-FileHash -LiteralPath $buddy -Algorithm SHA256).Hash.ToLowerInvariant())"
    $entryPoint=if($Production){'ModStudioEarlyAgent'}else{'StartupAgent'}
    $manifestText=@('Manifest-Version: 1.0',"Premain-Class: me.pavel.modstudio.startup.$entryPoint",'Can-Redefine-Classes: true','Can-Retransform-Classes: true',$version.Substring(0,70),(' '+$version.Substring(70)),$vendor.Substring(0,70),(' '+$vendor.Substring(70)),'','') -join ([string][char]13+[char]10)
    try{$writer.Write($manifestText)}finally{$writer.Dispose()}
    foreach($entry in $dependency.Entries){
        if((!$entry.FullName.StartsWith('net/bytebuddy/') -and $entry.FullName -notin @('META-INF/LICENSE','META-INF/NOTICE','META-INF/licenses/ASM')) -or $entry.FullName.EndsWith('/')){continue}
        $dest=$archive.CreateEntry($entry.FullName);$input=$entry.Open();$out=$dest.Open()
        try{$input.CopyTo($out)}finally{$input.Dispose();$out.Dispose()}
    }
    foreach($file in Get-ChildItem -LiteralPath $classes -File -Recurse){
        $dest=$archive.CreateEntry($file.FullName.Substring($classes.Length+1).Replace('\','/'));$input=$file.OpenRead();$out=$dest.Open()
        try{$input.CopyTo($out)}finally{$input.Dispose();$out.Dispose()}
    }
}finally{$dependency.Dispose();$archive.Dispose();$stream.Dispose()}
[IO.File]::Move($staged,$jar,$true)
Write-Output $jar
