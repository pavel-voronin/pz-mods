[CmdletBinding()]
param([string]$Game,[string]$Compiler)
$ErrorActionPreference='Stop'
$sourceRoot=Join-Path $PSScriptRoot 'Contents\mods\mod_studio\42.20.4\java\manifest-client'
$work=Join-Path $PSScriptRoot '.build\manifest-client'
$cache=Join-Path $env:TEMP 'PZModBuild'
$maven=Join-Path $cache 'apache-maven-3.9.11\bin\mvn.cmd'
if (!(Test-Path -LiteralPath $maven)) {
    $zip=Join-Path $cache 'apache-maven-3.9.11-bin.zip'
    if (!(Test-Path -LiteralPath $zip)) {Invoke-WebRequest -Uri 'https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.11/apache-maven-3.9.11-bin.zip' -OutFile $zip}
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA512).Hash -ne '03e2d65d4483a3396980629f260e25cac0d8b6f7f2791e4dc20bc83f9514db8d0f05b0479e699a5f34679250c49c8e52e961262ded468a20de0be254d8207076') {throw 'Maven checksum mismatch.'}
    Expand-Archive -LiteralPath $zip -DestinationPath $cache
}
New-Item -ItemType Directory -Path $work -Force | Out-Null
$deps=Join-Path $work 'dependencies'
$oldJavaHome=$env:JAVA_HOME
try {
    $env:JAVA_HOME=Join-Path $Game 'jre64'
    & $maven -B -q -f (Join-Path $sourceRoot 'pom.xml') "-Dmaven.repo.local=$cache\maven-repository" org.apache.maven.plugins:maven-dependency-plugin:3.8.1:copy-dependencies "-DoutputDirectory=$deps" -DincludeScope=runtime | Out-Host
    if ($LASTEXITCODE -ne 0) {throw 'Manifest dependency resolution failed.'}
} finally {$env:JAVA_HOME=$oldJavaHome}
$jars=@(Get-ChildItem -LiteralPath $deps -Filter '*.jar' | Sort-Object Name)
$sources=@(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'src') -Filter '*.java' -Recurse)
$resources=@(Get-ChildItem -LiteralPath (Join-Path $sourceRoot 'resources') -File -Recurse)
$fingerprint=($jars+$sources+$resources+(Get-Item -LiteralPath $PSCommandPath) | ForEach-Object {(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}) -join ''
$output=Join-Path $work 'manifest-client.jar'
$stamp=Join-Path $work 'inputs.sha256'
if ((Test-Path -LiteralPath $output) -and (Test-Path -LiteralPath $stamp) -and [IO.File]::ReadAllText($stamp) -eq $fingerprint) {return $output}
$classes=Join-Path $work ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $classes -Force | Out-Null
& (Join-Path $Game 'jre64\bin\java.exe') -jar $Compiler -25 -encoding UTF-8 -proc:none -nowarn -classpath (($jars | ForEach-Object FullName)-join ';') -d $classes @($sources | ForEach-Object FullName) | Out-Host
if ($LASTEXITCODE -ne 0) {throw 'Manifest client compilation failed.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream=[IO.File]::Create($output)
$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
$seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$services=@{}
function Add-Entry([string]$name,[byte[]]$bytes) {
    if (!$seen.Add($name)) {return}
    $entry=$archive.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
    $entry.LastWriteTime=[DateTimeOffset]::new(2026,1,1,0,0,0,[TimeSpan]::Zero)
    $out=$entry.Open();try {$out.Write($bytes,0,$bytes.Length)} finally {$out.Dispose()}
}
try {
    Add-Entry 'META-INF/MANIFEST.MF' ([Text.Encoding]::UTF8.GetBytes("Manifest-Version: 1.0`r`nMulti-Release: true`r`n`r`n"))
    foreach ($jar in $jars) {
        $input=[IO.Compression.ZipFile]::OpenRead($jar.FullName)
        try {foreach ($entry in $input.Entries) {
            $name=$entry.FullName
            if ($name.EndsWith('/') -or $name -match '(^|/)module-info.class$|^META-INF/(MANIFEST.MF|[^/]+\.(SF|RSA|DSA|EC))$') {continue}
            $data=[IO.MemoryStream]::new();$part=$entry.Open()
            try {$part.CopyTo($data);$bytes=$data.ToArray()} finally {$part.Dispose();$data.Dispose()}
            if ($name.StartsWith('META-INF/services/')) {$services[$name]=[string]$services[$name]+[Text.Encoding]::UTF8.GetString($bytes)+"`n";continue}
            # Keep each dependency's copyright/license and Maven metadata in the signed library.
            if (!$name.EndsWith('.class') -and $name -match '(?i)(^|/)(license|notice|copying)(\.|$|/)') {$name='META-INF/third-party/'+$jar.BaseName+'/'+$name}
            Add-Entry $name $bytes
        }} finally {$input.Dispose()}
    }
    foreach ($name in $services.Keys) {Add-Entry $name ([Text.Encoding]::UTF8.GetBytes($services[$name]))}
    foreach ($file in $resources) {
        Add-Entry ($file.FullName.Substring((Join-Path $sourceRoot 'resources').Length+1).Replace('\','/')) ([IO.File]::ReadAllBytes($file.FullName))
    }
    foreach ($file in (Get-ChildItem -LiteralPath $classes -File -Recurse | Sort-Object FullName)) {
        Add-Entry ($file.FullName.Substring($classes.Length+1).Replace('\','/')) ([IO.File]::ReadAllBytes($file.FullName))
    }
} finally {$archive.Dispose();$stream.Dispose()}
[IO.File]::WriteAllText($stamp,$fingerprint)
return $output
