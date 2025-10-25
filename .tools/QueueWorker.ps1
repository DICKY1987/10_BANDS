param(
    [string]$ConfigPath = ".\Config\CliToolsConfig.psd1"
)

# Load domain module
if (Test-Path "./libs/domain/AutomationCore.psm1") {
    Import-Module ./libs/domain/AutomationCore.psm1 -Force -ErrorAction Stop
} elseif (Test-Path "./AutomationSuite/AutomationSuite.psm1") {
    Import-Module ./AutomationSuite/AutomationSuite.psm1 -Force -ErrorAction Stop
}

# Load config
if (-not (Test-Path $ConfigPath)) { Write-Error "ConfigPath not found: $ConfigPath"; exit 2 }
$config = . $ConfigPath

$queueDir = $config.QueuePath -or Join-Path $env:TEMP "10_bands_queue"
$processingDir = Join-Path $queueDir "processing"
$doneDir = Join-Path $queueDir "done"
foreach ($d in @($queueDir, $processingDir, $doneDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }

Write-Host "QueueWorker started. Watching $queueDir"

while ($true) {
    try {
        $taskFile = Get-ChildItem -Path (Join-Path $queueDir "*.jsonl") -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $taskFile) {
            Start-Sleep -Seconds 2
            continue
        }

        $processingPath = Join-Path $processingDir $taskFile.Name
        Move-Item -Path $taskFile.FullName -Destination $processingPath -Force

        # Parse and validate task (placeholder)
        $taskJson = Get-Content -Path $processingPath -Raw
        $task = $taskJson | ConvertFrom-Json

        # Validate tool is whitelisted in config (simple example)
        if (-not ($config.Tools.Keys -contains $task.tool)) {
            Write-Warning "Tool $($task.tool) not whitelisted. Marking task failed."
            Move-Item -Path $processingPath -Destination (Join-Path $doneDir ($taskFile.BaseName + ".failed")) -Force
            continue
        }

        $toolCfg = $config.Tools[$task.tool]

        # Use domain function to start job (Start-AutomationCliJob is an example)
        if (Get-Command -Name Start-AutomationCliJob -ErrorAction SilentlyContinue) {
            Start-AutomationCliJob -ToolConfig $toolCfg -Arguments $task.args
        } else {
            # fallback: run process with full validation (placeholder)
            Start-Process -FilePath $toolCfg.Path -ArgumentList $task.args -NoNewWindow -Wait
        }

        Move-Item -Path $processingPath -Destination (Join-Path $doneDir $taskFile.Name) -Force
    } catch {
        Write-Error "Worker error: $_"
        Start-Sleep -Seconds 5
    }
}
