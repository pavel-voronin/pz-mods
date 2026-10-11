[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Output,[Parameter(Mandatory=$true)][string]$StopFile)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$log=[IO.StreamWriter]::new((Join-Path $Output 'system.jsonl'),$false,[Text.UTF8Encoding]::new($false))
try {
    while(!(Test-Path -LiteralPath $StopFile)){
        $sample=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');monotonic_ns=[long]([Diagnostics.Stopwatch]::GetTimestamp()*1e9/[Diagnostics.Stopwatch]::Frequency)}
        $processes=@(Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe' OR Name = 'ProjectZomboid64.exe'")
        $sample.java=@($processes | ForEach-Object {
            $p=Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
            @{pid=$_.ProcessId;command=$_.CommandLine;cpu_seconds=if($p){$p.CPU}else{$null};working_set=if($p){$p.WorkingSet64}else{$null};private_bytes=if($p){$p.PrivateMemorySize64}else{$null}}
        })
        $sample.gpu=(& nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,clocks.gr,clocks.mem,memory.used --format=csv,noheader,nounits 2>$null) -join ''
        $log.WriteLine(($sample | ConvertTo-Json -Depth 5 -Compress));$log.Flush()
        Start-Sleep -Seconds 5
    }
}finally{$log.Dispose()}
