# scripts/Supervisor.ps1
[CmdletBinding()]param(
  [string]$Worker = (Join-Path $PSScriptRoot 'QueueWorker.ps1'),
  [int]$HeartbeatStaleSec = 20
)
$ErrorActionPreference='Stop'
$hbPath = Join-Path $PSScriptRoot '..\.state\heartbeat.json'
New-Item -ItemType Directory -Force -Path (Split-Path $hbPath) | Out-Null

function Start-Worker {
  Start-Process pwsh -ArgumentList @('-NoProfile','-File', $Worker) -PassThru
}

$proc = Start-Worker
Write-Host "Supervisor: started PID $($proc.Id)"

while ($true) {
  Start-Sleep -Seconds 5
  $alive = $proc -and !$proc.HasExited
  $stale = $true
  if (Test-Path $hbPath) {
    try {
      $ts = (Get-Content $hbPath -Raw | ConvertFrom-Json).timestamp
      $stale = ((Get-Date) - ([datetime]$ts)).TotalSeconds -gt $HeartbeatStaleSec
    } catch { $stale = $true }
  }
  if (-not $alive -or $stale) {
    if ($alive) { try { $proc.Kill() } catch {} }
    Write-Host "Supervisor: restarting worker (alive=$alive, stale=$stale)"
    $proc = Start-Worker
  }
}
