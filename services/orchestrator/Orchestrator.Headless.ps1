# Orchestrator.Headless.ps1
# Runs all configured tools headlessly (no panes).
[CmdletBinding()]
param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot 'Config\CliToolsConfig.psd1'),
  [string]$SharedConfigPath = (Join-Path $PSScriptRoot 'SharedConfig.psd1')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Import AutomationSuite which should export Start-AutomationCliJob, Write-AutomationLog, etc.
$moduleCandidates = @(
  (Join-Path $PSScriptRoot 'AutomationSuite.psd1'),
  (Join-Path $PSScriptRoot 'AutomationSuite\AutomationSuite.psd1')
)
$modulePath = $moduleCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $modulePath) { throw "AutomationSuite module manifest not found (tried: $($moduleCandidates -join ', '))" }
Import-Module -Force $modulePath

# Load shared logging config (with sensible defaults if missing)
$cfg = if (Test-Path $SharedConfigPath) {
  try { Import-PowerShellDataFile -Path $SharedConfigPath } catch {
    @{ Logging=@{Enabled=$true;DefaultLevel='Info';LogPath=(Join-Path $PSScriptRoot 'logs')} }
  }
} else { @{ Logging=@{Enabled=$true;DefaultLevel='Info';LogPath=(Join-Path $PSScriptRoot 'logs')} } }

$logDir = $cfg.Logging.LogPath
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$corr  = ([Guid]::NewGuid().ToString('N')).Substring(0,8)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$unifiedLog = Join-Path $logDir "headless_$stamp.log"

if (-not (Test-Path $ConfigPath)) { throw "Tool config not found: $ConfigPath" }
$toolConfig = Import-PowerShellDataFile -Path $ConfigPath
$tools = @($toolConfig.Tools)

# Start jobs for each tool
$jobs = @()
foreach ($t in $tools) {
  try {
    if (-not ($t.Path -match '^[A-Za-z]:\\' -or $t.Path -match '^\\\\')) {
      $t.Path = (Get-Command -Name $t.Path -ErrorAction Stop).Source
    }
  } catch {
    Write-AutomationLog -Level Error -Message "Tool '$($t.Name)' not found on PATH: $($t.Path)" -CorrelationId $corr
    continue
  }

  $job = Start-AutomationCliJob -ToolConfig $t
  Write-AutomationLog -Level Info -Message "Started job $($job.Id) for '$($t.Name)'" -Data @{ Path=$t.Path; Args=($t.Arguments -join ' ') } -CorrelationId $corr
  $jobs += [PSCustomObject]@{
    Name=$t.Name
    Job=$job
    Log=(Join-Path $logDir ("{0}_{1}.log" -f ($t.Name -replace '[^A-Za-z0-9_\-]','_'), $stamp))
    Color=$t.Color
  }
}

if ($jobs.Count -eq 0) { throw "No tools started. Nothing to do." }

$refreshMs = [int]($toolConfig.MonitorRefreshRateMs ?? 200)
$stopFile = Join-Path $PSScriptRoot 'STOP.HEADLESS'
"[$(Get-Date -Format o)] [INFO][$corr] Headless start. Tools: $($jobs.Name -join ', ')" | Add-Content -Path $unifiedLog

try {
  while ($true) {
    foreach ($entry in $jobs) {
      $job=$entry.Job
      if ($job -and $job.HasMoreData) {
        Receive-Job -Job $job -Keep | ForEach-Object {
          $row = "$(Get-Date -Format o) [$($entry.Name)] $($_.ToString().TrimEnd())"
          Add-Content -Path $unifiedLog -Value $row
          Add-Content -Path $entry.Log   -Value $row
        }
      }
    }
    if (Test-Path $stopFile) { Write-AutomationLog -Level Info -Message "Stop file detected. Stopping..." -CorrelationId $corr; break }
    if (@($jobs | Where-Object { $_.Job.State -eq 'Running' -or $_.Job.HasMoreData }).Count -eq 0) { break }
    Start-Sleep -Milliseconds $refreshMs
  }
} finally {
  foreach ($entry in $jobs) {
    try {
      Receive-Job -Job $entry.Job -ErrorAction SilentlyContinue | ForEach-Object {
        $row = "$(Get-Date -Format o) [$($entry.Name)] $($_.ToString().TrimEnd())"
        Add-Content -Path $unifiedLog -Value $row
        Add-Content -Path $entry.Log   -Value $row
      }
    } catch {}
  }
  $summary = $jobs | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Job.State }
  "[$(Get-Date -Format o)] [INFO][$corr] Final states → $($summary -join '; ')" | Add-Content -Path $unifiedLog
}

[PSCustomObject]@{
  CorrelationId=$corr
  UnifiedLog=$unifiedLog
  Tools=$jobs | Select-Object Name, @{n='JobId';e={$_.Job.Id}}, @{n='State';e={$_.Job.State}}, Log
}
