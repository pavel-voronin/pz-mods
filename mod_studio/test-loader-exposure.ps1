param([Parameter(Mandatory)][string]$CoreJar,[string]$Game='C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid')
$ErrorActionPreference='Stop'
$agentJar=& (Join-Path $PSScriptRoot 'build-early.ps1') -Game $Game
$probeRoot=Join-Path $PSScriptRoot ('.build/exposure-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
$java=Join-Path $Game 'jre64/bin/java.exe'
& $java -jar (Join-Path $env:TEMP 'PZModBuild/ecj-3.44.0.jar') -25 -proc:none -nowarn -classpath "$Game/projectzomboid.jar" -d $probeRoot (Join-Path $PSScriptRoot 'tests/me/pavel/modstudio/NativeLoaderExposureProbe.java')
if($LASTEXITCODE -ne 0){throw 'Native exposure probe compilation failed'}
. (Join-Path $PSScriptRoot 'game-session.ps1')
$lease=Start-ModStudioSession -Mode offline-exposure-test -Source $probeRoot
Push-Location -LiteralPath $Game
try{
    foreach($mode in @('native-only','early-enabled')){
        $options=@('-Djava.library.path=win64/;.','--enable-native-access=ALL-UNNAMED')
        $probeOptions=@()
        if($mode -eq 'early-enabled'){$options+="-javaagent:$agentJar";$probeOptions+='expect-ready'}
        $options+='-agentlib:pz3dLoader'
        & $java @options -cp "$probeRoot;$Game/projectzomboid.jar" me.pavel.modstudio.NativeLoaderExposureProbe $Game (Join-Path $probeRoot $mode) $CoreJar @probeOptions > (Join-Path $probeRoot ($mode+'.txt')) 2>&1
        if($LASTEXITCODE -ne 0){throw "Native exposure probe failed: $mode"}
        Write-Output "Native exposure mode: $mode"
        Get-Content -LiteralPath (Join-Path $probeRoot ($mode+'.txt')) -Tail 5
    }
}finally{Pop-Location;Stop-ModStudioSession $lease}
Write-Output "Native exposure artifacts: $probeRoot"
