param(
    [string]$ConfigPath = ".\Config\CliToolsConfig.psd1",
    [int]$HeartbeatIntervalSec = 30
)

$config = if (Test-Path $ConfigPath) { . $ConfigPath } else { @{ QueuePath = (Join-Path $env:TEMP '10_bands_queue'); WorkerCount = 1 } }

$heartbeatFile = Join-Path ($config.QueuePath -or (Join-Path $env:TEMP '10_bands_queue')) "supervisor.heartbeat"
Write-Host "Supervisor started. Heartbeat: $heartbeatFile"

while ($true) {
    try {
        # Write heartbeat
        $ts = (Get-Date).ToString("o")
        New-Item -Path $heartbeatFile -ItemType File -Force | Out-Null
        Set-Content -Path $heartbeatFile -Value $ts

        # Ensure worker jobs exist (simple logic: if less jobs than WorkerCount, restart)
        $desired = $config.WorkerCount -or 1
        $current = (Get-Job -Name 'QueueWorker-*' -State Running -ErrorAction SilentlyContinue)
        $currentCount = if ($null -eq $current) { 0 } else { $current.Count }
        if ($currentCount -lt $desired) {
            $toStart = $desired - $currentCount
            for ($i=1; $i -le $toStart; $i++) {
                $workerScript = Join-Path (Split-Path -Parent $PSCommandPath) "QueueWorker.ps1"
                if (Test-Path $workerScript) {
                    Start-Job -Name ("QueueWorker-Restart-" + [guid]::NewGuid()) -ScriptBlock { param($s, $c) & $s -ConfigPath $c } -ArgumentList $workerScript, $ConfigPath | Out-Null
                    Write-Host "Restarted QueueWorker"
                }
            }
        }

        Start-Sleep -Seconds $HeartbeatIntervalSec
    } catch {
        Write-Error "Supervisor error: $_"
        Start-Sleep -Seconds 10
    }
}