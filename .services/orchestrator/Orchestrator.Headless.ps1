<param>
[Parameter(Mandatory = $false)]
[string]$ConfigPath = ".\Config\CliToolsConfig.psd1"
</param>

# Load module (adjust path if modules are moved)
if (Test-Path "./libs/domain/AutomationCore.psm1") {
    Import-Module ./libs/domain/AutomationCore.psm1 -Force -ErrorAction Stop
} elseif (Test-Path "./AutomationSuite/AutomationSuite.psm1") {
    Import-Module ./AutomationSuite/AutomationSuite.psm1 -Force -ErrorAction Stop
} else {
    Write-Error "Automation module not found. Please ensure AutomationCore/AutomationSuite is present."
    exit 2
}

# Load config
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Config not found: $ConfigPath"
    exit 3
}
$config = . $ConfigPath

# Prepare logs / queue directories from config
$queuePath = $config.QueuePath  -or Join-Path $env:TEMP "10_bands_queue"
if (-not (Test-Path $queuePath)) { New-Item -ItemType Directory -Path $queuePath -Force | Out-Null }

Write-Host "Starting headless orchestrator. Queue: $queuePath"

# Start a supervisor as a job or process
$supervisorScript = (Join-Path (Split-Path -Parent $PSCommandPath) "..\tools\Supervisor.ps1")
if (-not (Test-Path $supervisorScript)) {
    Write-Host "Supervisor script missing at expected path: $supervisorScript"
} else {
    Start-Job -Name "10BandsSupervisor" -ScriptBlock { param($s) & $s } -ArgumentList $supervisorScript | Out-Null
    Write-Host "Supervisor started as background job."
}

# Start one or more QueueWorker processes as background jobs
$workers = $config.WorkerCount -or 1
for ($i=1; $i -le $workers; $i++) {
    $workerScript = (Join-Path (Split-Path -Parent $PSCommandPath) "..\tools\QueueWorker.ps1")
    if (Test-Path $workerScript) {
        Start-Job -Name "QueueWorker-$i" -ScriptBlock { param($s, $c) & $s -ConfigPath $c } -ArgumentList $workerScript, $ConfigPath | Out-Null
        Write-Host "Started QueueWorker-$i"
    } else {
        Write-Host "QueueWorker script missing: $workerScript"
    }
}

Write-Host "Headless orchestrator started. Use Get-Job to monitor.
