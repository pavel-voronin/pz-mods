function Invoke-ModStudioProcess {
    param([Diagnostics.ProcessStartInfo]$Start, $Launch, [string]$Output, [int]$TimeoutSeconds, [string]$ResultPath=(Join-Path $Output 'scenario-result.json'))
    $process=$null
    $launchPath=Join-Path $Output 'launch.json'
    try {
        $process=[Diagnostics.Process]::Start($Start)
        $Launch.pid=$process.Id;$Launch.status='launched'
        $Launch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchPath -Encoding utf8
        $watch=[Diagnostics.Stopwatch]::StartNew();$finishedAt=$null
        while(!$process.HasExited -and $watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            if(Test-Path -LiteralPath $resultPath){
                # A writer may still be replacing its result. Retry incomplete JSON.
                $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                if($result -and $result.status -ne 'running' -and $null -eq $finishedAt){$finishedAt=$watch.Elapsed.TotalSeconds}
            }
            if($null -ne $finishedAt -and $watch.Elapsed.TotalSeconds-$finishedAt -gt 20){break}
            Start-Sleep -Milliseconds 250
        }
        if(!$process.HasExited){throw 'Game exceeded launch or shutdown deadline'}
        if(!(Test-Path -LiteralPath $resultPath)){throw 'Game exited without a scenario result'}
        $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $Launch.status=$result.status;$Launch.reason=$result.reason
        if($result.status -ne 'complete'){throw "Scenario did not complete: $($result.reason)"}
        if($process.ExitCode -ne 0){throw "Game exited with code $($process.ExitCode)"}
    } catch {
        $Launch.status='failed';$Launch.reason=$_.Exception.Message
        throw
    } finally {
        # Only this invocation's Process object is ever terminated, including on errors.
        try {
            if($process){
                if(!$process.HasExited){$Launch.forcedExit=$true;$process.Kill();$process.WaitForExit()}
                $Launch.exited=$process.HasExited;$Launch.exitCode=$process.ExitCode
            }
        } finally {
            $Launch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchPath -Encoding utf8
            if($ResultPath -ne (Join-Path $Output 'scenario-result.json') -and (Test-Path -LiteralPath $ResultPath)){
                Copy-Item -LiteralPath $ResultPath -Destination (Join-Path $Output 'scenario-result.json')
            }
            $console=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid/console.txt'
            if($process -and (Test-Path -LiteralPath $console)){Copy-Item -LiteralPath $console -Destination (Join-Path $Output 'console.txt')}
            if($process){$process.Dispose()}
        }
    }
    Write-Output "Scenario status: $($Launch.status); game process exited."
}
