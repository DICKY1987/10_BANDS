<#
  Simple QueueWorker skeleton for headless orchestration.
  Will be expanded in Phase 2. This file intentionally minimal to be safe in CI.
#>

param(
    [string]$ConfigPath = "$PSScriptRoot/../Config/SharedConfig.psd1"
)

# Load configuration
if (Test-Path -LiteralPath $ConfigPath) {
    $cfg = Import-PowerShellDataFile -Path $ConfigPath
}
else {
    Write-Warning "Config file not found: $ConfigPath"
    $cfg = @{ }
}

# Ensure directories exist
if ($cfg.LogPath) {
    if (-not (Test-Path -LiteralPath $cfg.LogPath)) {
        New-Item -Path $cfg.LogPath -ItemType Directory -Force | Out-Null
    }
}

Write-Output "QueueWorker starting (skeleton). Config loaded from: $ConfigPath"
# TODO: Implement queue polling, job creation, retry, metrics export