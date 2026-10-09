param([Parameter(Mandatory)][string]$StageJson,[string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$metadata=Get-Content -LiteralPath $StageJson -Raw | ConvertFrom-Json
if((Get-FileHash -LiteralPath $metadata.baseJar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $metadata.baseSha256){throw 'Installed base changed since staging; prepare a fresh stage'}
if((Get-FileHash -LiteralPath $metadata.jar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $metadata.jarSha256){throw 'Staged JAR fingerprint differs'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Read-ArchiveHashes([string]$Path){
    $archive=[IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entries=@{}
        foreach($entry in $archive.Entries){
            if($entries.ContainsKey($entry.FullName)){throw "Duplicate archive entry: $($entry.FullName)"}
            $stream=$entry.Open();$hash=[Security.Cryptography.SHA256]::Create()
            try{$entries[$entry.FullName]=[Convert]::ToHexString($hash.ComputeHash($stream))}finally{$hash.Dispose();$stream.Dispose()}
        }
        return $entries
    }finally{$archive.Dispose()}
}
$base=Read-ArchiveHashes $metadata.baseJar
$stage=Read-ArchiveHashes $metadata.jar
$allowed='^me/pavel/modstudio/(StartupPreparationPolicy|LuaPreparation|LuaPreparationHooks|LuaFolderScan|ScriptBlockParser|ItemParameterDispatch|StartupLuaDiagnostics|AnimationFrameCollector|AnimationKeyLookup|ClipFrameIndex|TranslationPreparation|SaveDirectoryPreparation)(\$[^/]+)?\.class$'
$preserved=0
foreach($name in $base.Keys){if($name -match $allowed){continue};if(!$stage.ContainsKey($name) -or $stage[$name] -ne $base[$name]){throw "Base archive entry changed: $name"};$preserved++}
foreach($name in $stage.Keys){if(!$base.ContainsKey($name) -and $name -notmatch $allowed){throw "Unexpected staged entry: $name"}}
foreach($name in @('StartupPreparationPolicy','LuaPreparation','LuaPreparationHooks','LuaFolderScan','ScriptBlockParser','ItemParameterDispatch','StartupLuaDiagnostics','AnimationFrameCollector','AnimationKeyLookup','ClipFrameIndex','TranslationPreparation','SaveDirectoryPreparation')){if(!$stage.ContainsKey("me/pavel/modstudio/$name.class")){throw "Missing preparation class: $name"}}
if(!(Test-Path -LiteralPath ($metadata.jar+'.zbs'))){throw 'Missing staged signature'}
if($metadata.installed){throw 'Expected an uninstalled stage'}
Write-Output "Staged archive PASS: $preserved base entries preserved exactly; only declared preparation classes added/replaced"
$compiler=Join-Path $env:TEMP 'PZModBuild/ecj-3.44.0.jar'
if((Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash -ne '14C46DDC2E511C46C998DA728F6A80F13A689C920F3832402F7AD150F6A6188D'){throw 'Unexpected compiler checksum'}
$classes=Join-Path (Split-Path $metadata.jar) 'signature-tests'
New-Item -ItemType Directory -Path $classes -Force | Out-Null
$java=Join-Path $Game 'jre64/bin/java.exe'
$classpath="$($metadata.jar);$Game/projectzomboid.jar;$Game/ZombieBuddy.jar"
& $java -jar $compiler -25 -proc:none -nowarn -classpath $classpath -d $classes (Join-Path $PSScriptRoot 'tests/me/pavel/modstudio/StartupPatchSignatureTest.java') (Join-Path $PSScriptRoot 'tests/me/pavel/modstudio/NativePatchEngineTest.java')
if($LASTEXITCODE -ne 0){throw 'Startup signature test compilation failed'}
& $java -cp "$classes;$classpath" me.pavel.modstudio.StartupPatchSignatureTest
if($LASTEXITCODE -ne 0){throw 'Startup strict matcher regression failed'}
& $java -cp "$classes;$classpath" me.pavel.modstudio.NativePatchEngineTest
if($LASTEXITCODE -ne 0){throw 'Installed native patch engine regression failed'}
& $java -cp "$classes;$classpath" me.pavel.modstudio.NativePatchEngineTest legacy
if($LASTEXITCODE -ne 0){throw 'Installed native patch engine negative control failed'}
