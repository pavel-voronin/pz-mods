function Invoke-ModStudioProcess {
    param([Diagnostics.ProcessStartInfo]$Start, $Launch, [string]$Output, [int]$TimeoutSeconds, [string]$ResultPath=(Join-Path $Output 'scenario-result.json'),[string]$ConsolePath='')
    $process=$null
    $launchPath=Join-Path $Output 'launch.json'
    try {
        $process=[Diagnostics.Process]::Start($Start)
        if(Get-Command Update-ModStudioSession -ErrorAction SilentlyContinue){Update-ModStudioSession -Session $modStudioSession -Phase loading -Artifact $Output -Process $process}
        $Launch.pid=$process.Id;$Launch.status='launched'
        $Launch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchPath -Encoding utf8
        $watch=[Diagnostics.Stopwatch]::StartNew();$finishedAt=$null;$detached=$false;$progressAt=0;$progressPhase=''
        while(!$process.HasExited -and $watch.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            if(Test-Path -LiteralPath $resultPath){
                # Native result writes briefly hold an exclusive file handle.
                # Retry that IO race as well as incomplete JSON within the deadline.
                $result=$null
                try {$result=Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction SilentlyContinue}
                catch [System.IO.IOException] {}
                if($result -and $result.status -eq 'interactive'){$detached=$true;break}
                if($result -and $result.status -ne 'running' -and $null -eq $finishedAt){$finishedAt=$watch.Elapsed.TotalSeconds}
                if($result -and (Get-Command Update-ModStudioSession -ErrorAction SilentlyContinue)){Update-ModStudioSession -Session $modStudioSession -Phase $result.status}
            }
            if($null -ne $finishedAt -and $watch.Elapsed.TotalSeconds-$finishedAt -gt 20){break}
            if($watch.Elapsed.TotalSeconds -ge $progressAt){
                $progressAt=$watch.Elapsed.TotalSeconds+15
                $progressPath=Join-Path $Output 'progress.json'
                if(Test-Path -LiteralPath $progressPath){
                    try{$progress=Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json
                        $timer=if($progress.exact_timer){'left'}else{'limit'}
                        if(Get-Command Update-ModStudioSession -ErrorAction SilentlyContinue){Update-ModStudioSession -Session $modStudioSession -Phase ("scenario: "+$progress.command)}
                        Write-Output ("Scenario {0}/{1}: {2} | {3} {4:N0}s | next {5} | input blocked={6}" -f $progress.step,$progress.total,$progress.command,$timer,$progress.left_seconds,$progress.next,$progress.input_blocked)
                    }catch [System.IO.IOException] {}
                }
            }
            Start-Sleep -Milliseconds 250
        }
        if(!$detached -and !$process.HasExited){throw 'Game exceeded launch or shutdown deadline'}
        if(!(Test-Path -LiteralPath $resultPath)){throw 'Game exited without a scenario result'}
        $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        $Launch.status=$result.status;$Launch.reason=$result.reason
        if($result.status -notin @('complete','interactive')){throw "Scenario did not complete: $($result.reason)"}
        if(!$detached -and $process.ExitCode -ne 0){throw "Game exited with code $($process.ExitCode)"}
    } catch {
        $Launch.status='failed';$Launch.reason=$_.Exception.Message
        throw
    } finally {
        # Only this invocation's Process object is ever terminated, including on errors.
        try {
            if($process){
                if(!$detached -and !$process.HasExited){$Launch.forcedExit=$true;$process.Kill();$process.WaitForExit()}
                $Launch.exited=$process.HasExited;if($process.HasExited){$Launch.exitCode=$process.ExitCode};$Launch.manualControl=$detached
            }
        } finally {
            $Launch | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchPath -Encoding utf8
            if($ResultPath -ne (Join-Path $Output 'scenario-result.json') -and (Test-Path -LiteralPath $ResultPath)){
                Copy-Item -LiteralPath $ResultPath -Destination (Join-Path $Output 'scenario-result.json')
            }
            $console=if($ConsolePath){$ConsolePath}else{Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Zomboid/console.txt'}
            if($process -and (Test-Path -LiteralPath $console)){Copy-Item -LiteralPath $console -Destination (Join-Path $Output 'console.txt')}
            if($process){$process.Dispose()}
        }
    }
    Write-Output "Scenario status: $($Launch.status); setup finished (manual sessions remain open)."
}
